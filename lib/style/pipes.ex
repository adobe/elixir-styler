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

  # we're in a multi-pipe, so only need to fix pipe_start
  def run({{:|>, _, [{:|>, _, _} | _]}, _} = zipper, ctx), do: {:cont, zipper |> check_start() |> Zipper.next(), ctx}
  # this is a single pipe, since valid pipelines are consumed by the previous head
  def run({{:|>, meta, [lhs, {fun, _, args}]}, _} = zipper, ctx) do
    if valid_pipe_start?(lhs) do
      # `a |> f(b, c)` => `f(a, b, c)`
      {:cont, Zipper.replace(zipper, {fun, meta, [lhs | args]}), ctx}
    else
      zipper = fix_start(zipper)
      {maybe_block, _, _} = lhs

      if maybe_block in @blocks do
        # extracting a block means this is now `if_result |> single_pipe(a, b)`
        # recursing will give us `single_pipe(if_result, a, b)`
        run(zipper, ctx)
      else
        # fixing the start when it was a function call added another pipe to the chain, and so it's no longer
        # a single pipe
        {:cont, zipper, ctx}
      end
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  # walking down a pipeline.
  # for reference, `a |> b() |> c()` is encoded `{:|>, [{:|>, _, [a, b]}, c]}`
  # that is, the outermost ast is the last step of the chain, and the innermost pipe is the first step of the chain
  defp check_start({{:|>, _, [{:|>, _, _} | _]}, _} = zipper), do: zipper |> Zipper.next() |> check_start()
  # we found the pipe starting expression!
  defp check_start({{:|>, _, [lhs, _]}, _} = zip), do: if(valid_pipe_start?(lhs), do: zip, else: fix_start(zip))
  defp check_start(zipper), do: zipper

  # this rewrites pipes that begin with blocks to save the result of the block expression into its own (non-hygienic!)
  # variable, and then use that variable as the start of the pipe. the variable is named after the type of block:
  # `case_result` or `if_result`
  #
  # before:
  #
  #   case ... do
  #     ...
  #   end
  #   |> a()
  #   |> b()
  #
  # after:
  #
  #   case_result =
  #     case ... do
  #       ...
  #     end
  #
  #   case_result
  #   |> a()
  #   |> b()
  defp fix_start({{:|>, pipe_meta, [{block, _, _} = expression, rhs]}, _} = zipper) when block in @blocks do
    variable = {:"#{block}_result", [], nil}

    zipper
    |> Zipper.replace({:|>, pipe_meta, [variable, rhs]})
    |> find_valid_assignment_location()
    |> Zipper.insert_left({:=, [], [variable, expression]})
  end

  # this rewrites other invalid pipe starts: `Module.foo(...) |> ...` and `foo(...) |> ....`
  defp fix_start({{:|>, pipe_meta, [lhs, rhs]}, _} = zipper) do
    lhs_rewrite =
      case lhs do
        # `Module.foo(a, ...)` => `a |> Module.foo(...)`
        {{:., dot_meta, dot_args}, args_meta, [arg | args]} ->
          {:|>, args_meta, [arg, {{:., [], dot_args}, dot_meta, args}]}

        # `foo(a, ...)` => `a |> foo(...)`
        {atom, meta, [arg | args]} ->
          {:|>, [], [arg, {atom, meta, args}]}
      end

    zipper |> Zipper.replace({:|>, pipe_meta, [lhs_rewrite, rhs]}) |> Zipper.next()
  end

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
  @math_operators ~w(- * + / > < <= >=)a
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
