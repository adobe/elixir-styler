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
    * Credo.Check.Readability.OneArityFunctionInPipe
    * Credo.Check.Readability.PipeIntoAnonymousFunctions
    * Credo.Check.Readability.SinglePipe
    * Credo.Check.Refactor.FilterCount
    * Credo.Check.Refactor.MapInto
    * Credo.Check.Refactor.MapJoin
    * Credo.Check.Refactor.PipeChainStart, excluded_functions: ["from"]
  """

  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  def run({{:|>, _, _}, _} = zipper, ctx) do
    case fix_pipe_start(zipper) do
      {{:|>, _, _}, _} = zipper ->
        case Zipper.traverse(zipper, fn {node, meta} -> {fix_pipe(node), meta} end) do
          {{:|>, _, [{:|>, _, _}, _]}, _} = chain_zipper ->
            {:cont, find_pipe_start(chain_zipper), ctx}

          # don't un-pipe into unquotes, as some expressions are only valid as pipes
          {{:|>, _, [_, {:unquote, _, [_]}]}, _} = single_pipe_unquote_zipper ->
            {:cont, single_pipe_unquote_zipper, ctx}

          {{:|>, _, [lhs, rhs]}, _} = single_pipe_zipper ->
            {_, meta, _} = lhs
            lhs = Style.set_line(lhs, meta[:line])
            {fun, meta, args} = Style.set_line(rhs, meta[:line])
            function_call_zipper = Zipper.replace(single_pipe_zipper, {fun, meta, [lhs | args || []]})
            {:cont, function_call_zipper, ctx}
        end

      non_pipe ->
        {:cont, non_pipe, ctx}
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
        |> Style.find_nearest_block()
        |> Zipper.insert_left(new_assignment)
        |> Zipper.left()
      else
        fix_pipe_start({pipe, zmeta})
      end
    end
  end

  defp find_pipe_start(zipper) do
    Zipper.find(zipper, fn
      {:|>, _, [{:|>, _, _}, _]} -> false
      {:|>, _, _} -> true
    end)
  end

  defp extract_start({fun, meta, [arg | args]} = lhs) do
    line = meta[:line]

    # is it a do-block macro style invocation?
    # if so, store the block result in a var and start the pipe w/ that
    if Enum.any?([arg | args], &match?([{{:__block__, _, [:do]}, _} | _], &1)) do
      # `block [foo] do ... end |> ...`
      # =======================>
      # block_result =
      #   block [foo] do
      #     ...
      #   end
      #
      # block_result
      # |> ...
      var_name =
        case fun do
          fun when is_atom(fun) -> fun
          {:., _, [{:__aliases__, _, _}, fun]} when is_atom(fun) -> fun
          _ -> "block"
        end

      variable = {:"#{var_name}_result", [line: line], nil}
      new_assignment = {:=, [line: line], [variable, lhs]}
      {variable, new_assignment}
    else
      # looks like it's just a normal function, so lift the first arg up into a new pipe
      # `foo(a, ...) |> ...` => `a |> foo(...) |> ...`
      arg =
        case arg do
          # If the first arg is a syntax-sugared kwl, we need to manually desugar it to cover all scenarios
          [{{:__block__, bm, _}, {:__block__, _, _}} | _] ->
            if bm[:format] == :keyword do
              {:__block__, [line: line, closing: [line: line]], [arg]}
            else
              arg
            end

          arg ->
            arg
        end

      {{:|>, [line: line], [arg, {fun, meta, args}]}, nil}
    end
  end

  # `pipe_chain(a, b, c)` generates the ast for `a |> b |> c`
  # the intention is to make it a little easier to see what the fix_pipe functions are matching on =)
  defmacrop pipe_chain(a, b, c) do
    quote do: {:|>, _, [{:|>, _, [unquote(a), unquote(b)]}, unquote(c)]}
  end

  # a |> fun => a |> fun()
  defp fix_pipe({:|>, m, [lhs, {fun, m2, nil}]}), do: {:|>, m, [lhs, {fun, m2, []}]}
  # Credo.Check.Readability.PipeIntoAnonymousFunctions
  # rewrite anonymous function invocation to use `then/2`
  # `a |> (& &1).() |> c()` => `a |> then(& &1) |> c()`
  defp fix_pipe({:|>, m, [lhs, {{:., m2, [{anon_fun, _, _}] = fun}, _, []}]}) when anon_fun in [:&, :fn],
    do: {:|>, m, [lhs, {:then, m2, fun}]}

  # `|> Timex.now()` => `|> DateTime.now!()`
  defp fix_pipe({:|>, m, [lhs, {{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, []}]}),
    do: {:|>, m, [lhs, {{:., dm, [{:__aliases__, am, [:DateTime]}, :now!]}, funm, []}]}

  # `lhs |> Enum.reverse() |> Enum.concat(enum)` => `lhs |> Enum.reverse(enum)`
  defp fix_pipe(
         pipe_chain(
           lhs,
           {{:., _, [{_, _, [:Enum]}, :reverse]} = reverse, meta, []},
           {{:., _, [{_, _, [:Enum]}, :concat]}, _, [enum]}
         )
       ) do
    {:|>, [line: meta[:line]], [lhs, {reverse, [line: meta[:line]], [enum]}]}
  end

  # `lhs |> Enum.filter(filterer) |> Enum.count()` => `lhs |> Enum.count(count)`
  defp fix_pipe(
         pipe_chain(
           lhs,
           {{:., _, [{_, _, [:Enum]}, :filter]}, meta, [filterer]},
           {{:., _, [{_, _, [:Enum]}, :count]} = count, _, []}
         )
       ) do
    {:|>, [line: meta[:line]], [lhs, {count, [line: meta[:line]], [filterer]}]}
  end

  # `lhs |> Enum.map(mapper) |> Enum.join(joiner)` => `lhs |> Enum.map_join(joiner, mapper)`
  defp fix_pipe(
         pipe_chain(
           lhs,
           {{:., dm, [{_, _, [:Enum]} = enum, :map]}, em, [mapper]},
           {{:., _, [{_, _, [:Enum]}, :join]}, _, [joiner]}
         )
       ) do
    rhs = Style.set_line({{:., dm, [enum, :map_join]}, em, [joiner, mapper]}, dm[:line])
    {:|>, [line: dm[:line]], [lhs, rhs]}
  end

  # `lhs |> Enum.map(mapper) |> Enum.into(empty_map)` => `lhs |> Map.new(mapper)
  # or
  # `lhs |> Enum.map(mapper) |> Enum.into(collectable)` => `lhs |> Enum.into(collectable, mapper)
  defp fix_pipe(
         pipe_chain(
           lhs,
           {{:., dm, [{_, am, [:Enum]}, :map]}, em, [mapper]},
           {{:., _, [{_, _, [:Enum]}, :into]} = into, _, [collectable]}
         )
       ) do
    rhs =
      if Style.empty_map?(collectable),
        do: {{:., dm, [{:__aliases__, am, [:Map]}, :new]}, em, [mapper]},
        else: {into, em, [collectable, mapper]}

    Style.set_line({:|>, [], [lhs, rhs]}, dm[:line])
  end

  defp fix_pipe({:|>, meta, [lhs, {{:., dm, [{_, am, [:Enum]}, :into]}, em, [collectable | rest]}]} = node) do
    if Style.empty_map?(collectable),
      do: {:|>, meta, [lhs, {{:., dm, [{:__aliases__, am, [:Map]}, :new]}, em, rest}]},
      else: node
  end

  for mod <- [:Map, :Keyword] do
    # lhs |> Map.merge(%{key: value}) => lhs |> Map.put(key, value)
    defp fix_pipe({:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(mod)]} = mod, :merge]}, m, [{:%{}, _, [{key, value}]}]}]}),
      do: {:|>, pm, [lhs, {{:., dm, [mod, :put]}, m, [key, value]}]}

    # lhs |> Map.merge(key: value) => lhs |> Map.put(:key, value)
    defp fix_pipe({:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(mod)]} = module, :merge]}, m, [[{key, value}]]}]}),
      do: {:|>, pm, [lhs, {{:., dm, [module, :put]}, m, [key, value]}]}
  end

  defp fix_pipe(node), do: node

  # most of these values were lifted directly from credo's pipe_chain_start.ex
  @literal ~w(__block__ __aliases__ unquote)a
  @value_constructors ~w(% %{} .. ..// <<>> @ {} ^ & fn from)a
  @infix_ops ~w(++ -- && || in - * + / > < <= >= == and or != !== ===)a
  @binary_ops ~w(<> <- ||| &&& <<< >>> <<~ ~>> <~ ~> <~> <|> ^^^ ~~~)a
  @valid_starts @literal ++ @value_constructors ++ @infix_ops ++ @binary_ops

  defp valid_pipe_start?({op, _, _}) when op in @valid_starts, do: true
  # 0-arity Module.function_call()
  defp valid_pipe_start?({{:., _, _}, _, []}), do: true
  # Exempt ecto's `from`
  defp valid_pipe_start?({{:., _, [{_, _, [:Query]}, :from]}, _, _}), do: true
  defp valid_pipe_start?({{:., _, [{_, _, [:Ecto, :Query]}, :from]}, _, _}), do: true
  # map[:foo]
  defp valid_pipe_start?({{:., _, [Access, :get]}, _, _}), do: true
  # 'char#{list} interpolation'
  defp valid_pipe_start?({{:., _, [List, :to_charlist]}, _, _}), do: true
  # n-arity Module.function_call(...args)
  defp valid_pipe_start?({{:., _, _}, _, _}), do: false
  # variable
  defp valid_pipe_start?({variable, _, nil}) when is_atom(variable), do: true
  # 0-arity function_call()
  defp valid_pipe_start?({fun, _, []}) when is_atom(fun), do: true
  # function_call(with, args) or sigils. sigils are allowed, function w/ args is not
  defp valid_pipe_start?({fun, _, _args}) when is_atom(fun), do: String.match?("#{fun}", ~r/^sigil_[a-zA-Z]$/)
  defp valid_pipe_start?(_), do: true
end
