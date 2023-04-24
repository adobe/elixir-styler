# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Pipes do
  @moduledoc """
  Styles pipes! In particular, don't make pipe chains of only one pipe, and some persnickety pipe chain start stuff.

  Rewrites for the following Credo rules:

    * Credo.Check.Readability.BlockPipe
    * Credo.Check.Readability.SinglePipe
    * Credo.Check.Refactor.PipeChainStart, excluded_functions: ["from"]

  The following two rules are only corrected within pipe chains; nested functions aren't fixed

    * Credo.Check.Refactor.FilterCount
    * Credo.Check.Refactor.MapJoin
    * Credo.Check.Refactor.MapInto
  """

  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  @blocks ~w(case if with cond for unless)a

  def run({{:|>, _, _} = pipe, zmeta} = zipper, ctx) do
    {{:|>, pipe_meta, [lhs, rhs]}, _} = start_zipper = find_pipe_start({pipe, nil})

    # Fix invalid starts
    zipper =
      if valid_pipe_start?(lhs) do
        zipper
      else
        {lhs_rewrite, new_assignment} = extract_start(lhs)

        {pipe, nil} =
          start_zipper
          |> Zipper.replace({:|>, pipe_meta, [lhs_rewrite, rhs]})
          |> Zipper.top()

        if new_assignment do
          # It's important to note that with this branch, we're no longer
          # focused on the pipe! We'll return to it in a future iteration of traverse_while
          {pipe, zmeta}
          |> Style.ensure_block_parent()
          |> Zipper.insert_left(new_assignment)
          |> Zipper.left()
        else
          {pipe, zmeta}
        end
      end

    # Optimize and collapse the pipe
    zipper =
      case Zipper.traverse(zipper, &optimize/1) do
        {{:|>, _, [{:|>, _, _}, _]}, _} = chain_zipper ->
          find_pipe_start(chain_zipper)

        {{:|>, _, [lhs, {fun, meta, args}]}, _} = single_pipe_zipper ->
          lhs = Style.delete_line_meta(lhs)
          Zipper.replace(single_pipe_zipper, {fun, meta, [lhs | args || []]})

        above_the_pipe_zipper ->
          above_the_pipe_zipper
      end

    {:cont, zipper, ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp find_pipe_start(zipper) do
    Zipper.find(zipper, fn
      {:|>, _, [{:|>, _, _}, _]} -> false
      {:|>, _, [_, _]} -> true
    end)
  end

  # `block do ... end |> ...`
  # =======================>
  # block_result =
  #   block do
  #     ...
  #   end
  #
  # block_result
  # |> ...
  defp extract_start({block, _, _} = lhs) when block in @blocks do
    variable = {:"#{block}_result", [], nil}
    new_assignment = {:=, [], [variable, lhs]}
    {variable, new_assignment}
  end

  # `foo(a, ...) |> ...` => `a |> foo(...) |> ...`
  defp extract_start({fun, meta, [arg | args]}), do: {{:|>, [], [arg, {fun, meta, args}]}, nil}

  # `a |> Enum.filter(b) |> Enum.count()` => `a |> Enum.count(b)`
  defp optimize(
         {{:|>, _,
           [
             {:|>, _, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [filterer]}]},
             {{:., _, [{:__aliases__, _, [:Enum]}, :count]} = count, _, []}
           ]}, _} = zipper
       ) do
    Zipper.replace(zipper, {:|>, [], [lhs, {count, [], [filterer]}]})
  end

  # `Enum.map |> Enum.join` => `Enum.map_join`
  defp optimize(
         {{:|>, _,
           [
             {:|>, _, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [mapper]}]},
             {{:., _, [{:__aliases__, _, [:Enum]}, :join]}, _, [joiner]}
           ]}, _} = zipper
       ) do
    # Delete line info to keep things shrunk on the rewrite
    joiner = Style.delete_line_meta(joiner)
    mapper = Style.delete_line_meta(mapper)
    rhs = {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [joiner, mapper]}
    Zipper.replace(zipper, {:|>, [], [lhs, rhs]})
  end

  # `Enum.map |> Enum.into` => `Map.new`
  defp optimize(
         {{:|>, _,
           [
             {:|>, _, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :map]}, _, [mapper]}]},
             {{:., _, [{:__aliases__, _, [:Enum]}, :into]}, _, [collectable]}
           ]}, _} = zipper
       ) do
    mapper = Style.delete_line_meta(mapper)

    rhs =
      if empty_map?(collectable),
        do: {{:., [], [{:__aliases__, [], [:Map]}, :new]}, [], [mapper]},
        else: {{:., [], [{:__aliases__, [], [:Enum]}, :into]}, [], [collectable, mapper]}

    Zipper.replace(zipper, {:|>, [], [lhs, rhs]})
  end

  defp optimize(zipper), do: zipper

  defp empty_map?({:%{}, _, []}), do: true
  defp empty_map?({{:., _, [{:__aliases__, _, [:Map]}, :new]}, _, []}), do: true
  defp empty_map?(_), do: false

  # literal wrapper
  defp valid_pipe_start?({:__block__, _, _}), do: true
  defp valid_pipe_start?({:__aliases__, _, _}), do: true
  defp valid_pipe_start?({:unquote, _, _}), do: true
  # ecto
  defp valid_pipe_start?({:from, _, _}), do: true
  # most of these values were lifted directly from credo's pipe_chain_start.ex
  @value_constructors ~w(% %{} .. <<>> @ {} & fn)a
  @simple_operators ~w(++ -- && ||)a
  @math_operators ~w(- * + / > < <= >= ==)a
  @binary_operators ~w(<> <- ||| &&& <<< >>> <<~ ~>> <~ ~> <~> <|> ^^^ ~~~)a
  defp valid_pipe_start?({op, _, _})
       when op in @value_constructors or op in @simple_operators or op in @math_operators or op in @binary_operators,
       do: true

  # variable
  defp valid_pipe_start?({atom, _, nil}) when is_atom(atom), do: true
  # 0-arity function_call()
  defp valid_pipe_start?({atom, _, []}) when is_atom(atom), do: true
  # function_call(with, args) or sigils. sigils are allowed, function w/ args is not
  defp valid_pipe_start?({atom, _, [_ | _]}) when is_atom(atom), do: String.match?("#{atom}", ~r/^sigil_[a-zA-Z]$/)
  # map[:access]
  defp valid_pipe_start?({{:., _, [Access, :get]}, _, _}), do: true
  # Module.function_call()
  defp valid_pipe_start?({{:., _, _}, _, []}), do: true
  # '__#{val}__' are compiled to List.to_charlist("__#{val}__")
  # we want to consider these charlists a valid pipe chain start
  defp valid_pipe_start?({{:., _, [List, :to_charlist]}, _, [[_ | _]]}), do: true
  # Module.function_call(with, parameters)
  defp valid_pipe_start?({{:., _, _}, _, _}), do: false
  defp valid_pipe_start?(_), do: true
end
