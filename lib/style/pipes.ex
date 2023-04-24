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

  def run({{:|>, _, _}, _} = zipper, ctx) do
    case fix_pipe_start(zipper) do
      {{:|>, _, _}, _} = zipper -> {:cont, optimize_and_collapse(zipper), ctx}
      non_pipe -> {:cont, non_pipe, ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp fix_pipe_start({pipe, zmeta} = zipper) do
    {{:|>, pipe_meta, [lhs, rhs]}, _} = start_zipper = find_pipe_start({pipe, nil})

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
  end

  defp optimize_and_collapse({{:|>, _, _}, _} = zipper) do
    case Zipper.traverse(zipper, fn {node, meta} -> {optimize(node), meta} end) do
      {{:|>, _, [{:|>, _, _}, _]}, _} = chain_zipper ->
        find_pipe_start(chain_zipper)

      {{:|>, _, [lhs, {fun, meta, args}]}, _} = single_pipe_zipper ->
        lhs = Style.delete_line_meta(lhs)
        Zipper.replace(single_pipe_zipper, {fun, meta, [lhs | args || []]})
    end
  end

  defp find_pipe_start(zipper) do
    Zipper.find(zipper, fn
      {:|>, _, [{:|>, _, _}, _]} -> false
      {:|>, _, _} -> true
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
  defp extract_start({fun, meta, [arg | args]}) do
    {{:|>, [], [arg, {fun, meta, args}]}, nil}
  end

  # `pipe_chain(a, b, c)` generates the ast for `a |> b |> c`
  # the intention is to make it a little easier to see what the optimize functions are matching on =)
  defmacrop pipe_chain(a, b, c) do
    quote do: {:|>, _, [{:|>, _, [unquote(a), unquote(b)]}, unquote(c)]}
  end

  # `lhs |> Enum.filter(filterer) |> Enum.count()` => `lhs |> Enum.count(count)`
  defp optimize(
         pipe_chain(
           lhs,
           {{:., _, [{_, _, [:Enum]}, :filter]}, _, [filterer]},
           {{:., _, [{_, _, [:Enum]}, :count]} = count, _, []}
         )
       ) do
    {:|>, [], [lhs, {count, [], [filterer]}]}
  end

  # `lhs |> Enum.map(mapper) |> Enum.join(joiner)` => `lhs |> Enum.map_join(joiner, mapper)`
  defp optimize(
         pipe_chain(
           lhs,
           {{:., _, [{_, _, [:Enum]}, :map]}, _, [mapper]},
           {{:., _, [{_, _, [:Enum]}, :join]}, _, [joiner]}
         )
       ) do
    # Delete line info to keep things shrunk on the rewrite
    joiner = Style.delete_line_meta(joiner)
    mapper = Style.delete_line_meta(mapper)
    rhs = {{:., [], [{:__aliases__, [], [:Enum]}, :map_join]}, [], [joiner, mapper]}
    {:|>, [], [lhs, rhs]}
  end

  # `lhs |> Enum.map(mapper) |> Enum.into(empty_map)` => `lhs |> Map.new(mapper)
  # or
  # `lhs |> Enum.map(mapper) |> Enum.into(collectable)` => `lhs |> Enum.into(collectable, mapper)
  defp optimize(
         pipe_chain(
           lhs,
           {{:., _, [{_, _, [:Enum]}, :map]}, _, [mapper]},
           {{:., _, [{_, _, [:Enum]}, :into]} = into, _, [collectable]}
         )
       ) do
    mapper = Style.delete_line_meta(mapper)

    rhs =
      if empty_map?(collectable),
        do: {{:., [], [{:__aliases__, [], [:Map]}, :new]}, [], [mapper]},
        else: {into, [], [collectable, mapper]}

    {:|>, [], [lhs, rhs]}
  end

  defp optimize(node), do: node

  defp empty_map?({:%{}, _, []}), do: true
  defp empty_map?({{:., _, [{_, _, [:Map]}, :new]}, _, []}), do: true
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
