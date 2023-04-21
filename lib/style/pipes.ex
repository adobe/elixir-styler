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

  alias Styler.Style
  alias Styler.Zipper

  @blocks ~w(case if with cond for unless)a

  # we're in a multi-pipe, so only need to fix pipe_start
  def run({{:|>, _, [{:|>, _, _} | _]}, _} = zipper, ctx), do: {:cont, zipper |> check_start() |> Zipper.next(), ctx}
  # this is a single pipe, since valid pipelines are consumed by the previous head
  def run({{:|>, _, [lhs, {fun, meta, args}]}, _} = zipper, ctx) do
    if valid_pipe_start?(lhs) do
      # Set the lhs to be on the same line as the pipe - keeps the formatter from making a multiline invocation
      lhs = Macro.update_meta(lhs, &Keyword.replace(&1, :line, meta[:line]))
      # `a |> f(b, c)` => `f(a, b, c)`
      {:cont, Zipper.replace(zipper, {fun, meta, [lhs | args || []]}), ctx}
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
    |> Style.ensure_block_parent()
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
