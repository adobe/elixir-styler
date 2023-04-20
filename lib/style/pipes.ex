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
  """

  @behaviour Styler.Style

  alias Styler.Zipper

  @blocks ~w(case if with cond for unless)a

  def run({{:|>, _, _}, _} = zipper, ctx) do
    {zipper, new_assignment} =
      Zipper.traverse_while(zipper, nil, fn
        {{:|>, _, [{:|>, _, _}, _]}, _} = zipper, _ ->
          {:cont, zipper, nil}

        {{:|>, pipe_meta, [lhs, rhs]}, _} = zipper, _ ->
          if valid_pipe_start?(lhs) do
            {:halt, zipper, nil}
          else
            {lhs_rewrite, new_assignment} =
              case lhs do
                # `block do ... end |> ...`
                # =======================>
                # block_result =
                #   block do
                #     ...
                #   end
                #
                # block_result
                # |> ...
                {block, _, _} when block in @blocks ->
                  variable = {:"#{block}_result", [], nil}
                  new_assignment = {:=, [], [variable, lhs]}
                  {variable, new_assignment}

                # `Module.foo(a, ...) |> ...` => `a |> Module.foo(...) |> ...`
                {{:., dot_meta, dot_args}, args_meta, [arg | args]} ->
                  {{:|>, args_meta, [arg, {{:., [], dot_args}, dot_meta, args}]}, nil}

                # `foo(a, ...) |> ...` => `a |> foo(...) |> ...`
                {fun, meta, [arg | args]} ->
                  {{:|>, [], [arg, {fun, meta, args}]}, nil}
              end

            {:halt, Zipper.replace(zipper, {:|>, pipe_meta, [lhs_rewrite, rhs]}), new_assignment}
          end
      end)

    # We can't insert the sibling within the traverse_while because the traversal context is reset, so it wouldn't
    # be able to go all the way up to the parent level. now that we have full context again we'll do the insertion
    zipper =
      if new_assignment do
        zipper
        |> find_valid_assignment_location()
        |> Zipper.insert_left(new_assignment)
      else
        zipper
      end

    zipper =
      zipper
      |> Zipper.traverse(&optimize/1)
      |> collapse_single_pipe()
      |> Zipper.find(&(not match?({:|>, _, [{:|>, _, _}, _]}, &1)))

    {:cont, zipper, ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp collapse_single_pipe({{:|>, _, [{:|>, _, _} | _]}, _} = zipper), do: zipper
  # `a |> f(b, c)` => `f(a, b, c)`
  defp collapse_single_pipe({{:|>, _, [lhs, {fun, meta, args}]}, _} = zipper) do
    # Set the lhs to be on the same line as the pipe - keeps the formatter from making a multiline invocation
    lhs = Macro.update_meta(lhs, &Keyword.replace(&1, :line, meta[:line]))
    Zipper.replace(zipper, {fun, meta, [lhs | args || []]})
  end

  defp optimize(
         {{:|>, _,
           [
             {:|>, meta, [lhs, {{:., _, [{:__aliases__, _, [:Enum]}, :filter]}, _, [fun]}]},
             {{:., _, [{:__aliases__, _, [:Enum]}, :count]} = count, count_meta, []}
           ]}, _} = zipper
       ) do
    Zipper.replace(zipper, {:|>, meta, [lhs, {count, count_meta, [fun]}]})
  end

  defp optimize(zipper), do: zipper

  # this really needs a better name.
  # essentially what we're doing is walking up the tree in search of a parent where it would be syntactically valid
  # to insert a new "assignment" node (`x = y`)
  # as we walk up the tree, our parent will be either
  # 1. an invalid node for an assignment (still in the pipeline or in another assignment)
  # 2. the start of the context (function def start)
  # 3. something else!
  # for 1, we keep going up
  # for 2, we wrap ourselves in a new block parent (where we can insert a sibling node)
  # for 3, we're done - wherever it is we are, our parent already supports us inserting a sibling node
  defp find_valid_assignment_location(zipper) do
    case Zipper.up(zipper) do
      # still trying to find our way up the pipe, keep walking...
      {{:|>, _, _}, _} = parent -> find_valid_assignment_location(parent)
      # the parent of this pipe is an assignment like
      #
      #   baz =
      #     block do ... end
      #     |> ...
      #
      # so we need to step up again and see what the assignment's parent is, with the goal of inserting our new
      # assignment before the assignment built from the pipe chain, like:
      #
      #   block_result = block do ... end
      #   baz =
      #     block_result
      #     |> ...
      {{:=, _, _}, _} = parent -> find_valid_assignment_location(parent)
      # we're in a function which is an immediate pipeline, like:
      #
      # def fun do
      #   block do end
      #   |> f()
      # end
      {{{:__block__, _, _}, {:|>, _, _}}, _} -> wrap_in_block(zipper)
      # similar to the function definition, except it's an anonymous function this time
      #
      # fn ->
      #   case do end
      #   |> b()
      # end
      {{:->, _, [_, {:|>, _, _} | _]}, _} -> wrap_in_block(zipper)
      # a snippet or script where the problem block has no parent
      nil -> wrap_in_block(zipper)
      # since its parent isn't one of the problem AST above, the current zipper must be a valid place to insert the node
      _ -> zipper
    end
  end

  # give it a block parent, then step back to the pipe - we can insert next to it now that it's in a block
  defp wrap_in_block({node, _} = zipper) do
    zipper
    |> Zipper.replace({:__block__, [], [node]})
    |> Zipper.next()
  end

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
