# Copyright 2024 Adobe. All rights reserved.
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

  @collectable ~w(Map Keyword MapSet)a
  @enum ~w(Enum Stream)a

  # most of these values were lifted directly from credo's pipe_chain_start.ex
  @literal ~w(__block__ __aliases__ unquote)a
  @value_constructors ~w(% %{} .. ..// <<>> @ {} ^ & fn from)a
  @kernel_ops ~w(++ -- && || in - * + / > < <= >= == and or != !== === <> ! not)a
  @special_ops ~w(||| &&& <<< >>> <<~ ~>> <~ ~> <~>)a
  @special_ops @literal ++ @value_constructors ++ @kernel_ops ++ @special_ops

  def run({{:|>, _, _}, _} = zipper, ctx) do
    case fix_pipe_start(zipper) do
      {{:|>, _, _}, _} = zipper ->
        case Zipper.traverse(zipper, fn {node, meta} -> {fix_pipe(node), meta} end) do
          {{:|>, _, [{:|>, _, _}, _]}, _} = chain_zipper ->
            {:cont, find_pipe_start(chain_zipper), ctx}

          # don't un-pipe into unquotes, as some expressions are only valid as pipes
          {{:|>, _, [_, {:unquote, _, [_]}]}, _} = single_pipe_unquote_zipper ->
            {:cont, single_pipe_unquote_zipper, ctx}

          # unpipe a single pipe zipper
          {{:|>, _, [lhs, rhs]}, _} = single_pipe_zipper ->
            {fun, rhs_meta, args} = rhs
            {_, lhs_meta, _} = lhs
            lhs_line = lhs_meta[:line]
            args = args || []
            # Every branch ends with the zipper being replaced with a function call
            # `lhs |> rhs(...args)` => `rhs(lhs, ...args)`
            # The differences are just figuring out what line number updates to make
            # in order to get the following properties:
            #
            # 1. write the function call on one line if reasonable
            # 2. keep comments well behaved (by doing meta line-number gymnastics)

            # if we see multiple `->`, there's no way we can online this
            # future heuristics would include finding multiple lines
            definitively_multiline? =
              Enum.any?(args, fn
                {:fn, _, [{:->, _, _}, {:->, _, _} | _]} -> true
                {:fn, _, [{:->, _, [_, _]}]} -> true
                _ -> false
              end)

            if definitively_multiline? do
              # shift rhs up to hang out with lhs
              # 1   lhs
              # 2   |> fun(
              # 3     ...args...
              # n   )
              # =>
              # 1   fun(lhs
              # 2     ... args...
              # n-1 )

              # because there could be comments between lhs and rhs, or the dev may have a bunch of empty lines,
              # we need to calculate the distance between the two ("shift")
              rhs_line = rhs_meta[:line]
              shift = lhs_line - rhs_line
              {fun, meta, args} = Style.shift_line(rhs, shift)

              # Not going to lie, no idea why the `shift + 1` is correct but it makes tests pass ¯\_(ツ)_/¯
              rhs_max_line = Style.max_line(rhs)

              comments =
                ctx.comments
                |> Style.displace_comments(lhs_line..(rhs_line - 1))
                |> Style.shift_comments(rhs_line..rhs_max_line, shift + 1)

              {:cont, Zipper.replace(single_pipe_zipper, {fun, meta, [lhs | args]}), %{ctx | comments: comments}}
            else
              # try to get everything on one line.
              # formatter will kick it back to multiple if line-length doesn't accommodate
              case Zipper.up(single_pipe_zipper) do
                # if the parent is an assignment, put it on the same line as the `=`
                {{:=, am, [{_, vm, _} = var, _single_pipe]}, _} = assignment_parent ->
                  # 1 var =
                  # 2   lhs
                  # 3   |> rhs(...args)
                  # =>
                  # 1 var = rhs(lhs, ...args)
                  oneline_assignment = Style.set_line({:=, am, [var, {fun, rhs_meta, [lhs | args]}]}, vm[:line])
                  # skip so we don't re-traverse
                  {:cont, Zipper.replace(assignment_parent, oneline_assignment), ctx}

                _ ->
                  # lhs
                  # |> rhs(...args)
                  # =>
                  # rhs(lhs, ...)
                  oneline_function_call = Style.set_line({fun, rhs_meta, [lhs | args]}, lhs_line)
                  {:cont, Zipper.replace(single_pipe_zipper, oneline_function_call), ctx}
              end
            end
        end

      non_pipe ->
        {:cont, non_pipe, ctx}
    end
  end

  # a(b |> c[, ...args])
  # The first argument to a function-looking node is a pipe.
  # Maybe pipe the whole thing?
  def run({{f, m, [{:|>, _, _} = pipe | args]}, _} = zipper, ctx) do
    parent =
      case Zipper.up(zipper) do
        {{parent, _, _}, _} -> parent
        _ -> nil
      end

    stringified = is_atom(f) && to_string(f)

    cond do
      # this is likely a macro
      # assert a |> b() |> c()
      !m[:closing] ->
        {:cont, zipper, ctx}

      # leave bools alone as they often read better coming first, like when prepended with `not`
      # [not ]is_nil(a |> b() |> c())
      stringified && (String.starts_with?(stringified, "is_") or String.ends_with?(stringified, "?")) ->
        {:cont, zipper, ctx}

      # string interpolation, module attribute assignment, or prettier bools with not
      parent in [:"::", :@, :not, :|>] ->
        {:cont, zipper, ctx}

      # double down on being good to exunit macros, and any other special ops
      # ..., do: assert(a |> b |> c)
      # not (a |> b() |> c())
      f in [:assert, :refute | @special_ops] ->
        {:cont, zipper, ctx}

      # if a |> b() |> c(), do: ...
      Enum.any?(args, &Style.do_block?/1) ->
        {:cont, zipper, ctx}

      true ->
        {:cont, Zipper.replace(zipper, {:|>, m, [pipe, {f, m, args}]}), ctx}
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
          # unless will be rewritten to `if` statements in the Blocks Style
          :unless -> :if
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
  defmacrop pipe_chain(pm, a, b, c) do
    quote do: {:|>, _, [{:|>, unquote(pm), [unquote(a), unquote(b)]}, unquote(c)]}
  end

  # a |> fun => a |> fun()
  defp fix_pipe({:|>, m, [lhs, {fun, m2, nil}]}), do: {:|>, m, [lhs, {fun, m2, []}]}

  # a |> then(&fun(&1, d)) |> c => a |> fun(d) |> c()
  defp fix_pipe({:|>, m, [lhs, {:then, _, [{:&, _, [{fun, m2, [{:&, _, _} | args]}]}]}]} = pipe) do
    rewrite = {fun, m2, args}

    # if `&1` is referenced more than once, we have to continue using `then`
    cond do
      rewrite |> Zipper.zip() |> Zipper.any?(&match?({:&, _, _}, &1)) ->
        pipe

      fun in @special_ops ->
        # we only rewrite unary/infix operators if they're in the Kernel namespace.
        # everything else stays as-is in the `then/2` because we can't know what module they're from
        if fun in @kernel_ops,
          do: {:|>, m, [lhs, {{:., m2, [{:__aliases__, m2, [:Kernel]}, fun]}, m2, args}]},
          else: pipe

      true ->
        {:|>, m, [lhs, rewrite]}
    end
  end

  # a |> then(&fun/1) |> c => a |> fun() |> c()
  # recurses to add the `()` to `fun` as it gets unwound
  defp fix_pipe({:|>, m, [lhs, {:then, _, [{:&, _, [{:/, _, [{_, _, nil} = fun, {:__block__, _, [1]}]}]}]}]}),
    do: fix_pipe({:|>, m, [lhs, fun]})

  # Credo.Check.Readability.PipeIntoAnonymousFunctions
  # rewrite anonymous function invocation to use `then/2`
  # `a |> (& &1).() |> c()` => `a |> then(& &1) |> c()`
  defp fix_pipe({:|>, m, [lhs, {{:., m2, [{anon_fun, _, _}] = fun}, _, []}]}) when anon_fun in [:&, :fn],
    do: {:|>, m, [lhs, {:then, m2, fun}]}

  # `lhs |> Enum.reverse() |> Enum.concat(enum)` => `lhs |> Enum.reverse(enum)`
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., _, [{_, _, [:Enum]}, :reverse]} = reverse, meta, []},
           {{:., _, [{_, _, [:Enum]}, :concat]}, _, [enum]}
         )
       ) do
    {:|>, pm, [lhs, {reverse, [line: meta[:line]], [enum]}]}
  end

  # `lhs |> Enum.reverse() |> Kernel.++(enum)` => `lhs |> Enum.reverse(enum)`
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., _, [{_, _, [:Enum]}, :reverse]} = reverse, meta, []},
           {{:., _, [{_, _, [:Kernel]}, :++]}, _, [enum]}
         )
       ) do
    {:|>, pm, [lhs, {reverse, [line: meta[:line]], [enum]}]}
  end

  # `lhs |> Enum.filter(filterer) |> Enum.count()` => `lhs |> Enum.count(count)`
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., _, [{_, _, [mod]}, :filter]}, meta, [filterer]},
           {{:., _, [{_, _, [:Enum]}, :count]} = count, _, []}
         )
       )
       when mod in @enum do
    {:|>, pm, [lhs, {count, [line: meta[:line]], [filterer]}]}
  end

  # `lhs |> Stream.map(fun) |> Stream.run()` => `lhs |> Enum.each(fun)`
  # `lhs |> Stream.each(fun) |> Stream.run()` => `lhs |> Enum.each(fun)`
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., dm, [{a, am, [:Stream]}, map_or_each]}, fm, fa},
           {{:., _, [{_, _, [:Stream]}, :run]}, _, []}
         )
       )
       when map_or_each in [:map, :each] do
    {:|>, pm, [lhs, {{:., dm, [{a, am, [:Enum]}, :each]}, fm, fa}]}
  end

  # `lhs |> Enum.map(mapper) |> Enum.join(joiner)` => `lhs |> Enum.map_join(joiner, mapper)`
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., dm, [{_, _, [mod]}, :map]}, em, map_args},
           {{:., _, [{_, _, [:Enum]} = enum, :join]}, _, join_args}
         )
       )
       when mod in @enum do
    rhs = {{:., dm, [enum, :map_join]}, em, Style.set_line(join_args, dm[:line]) ++ map_args}
    {:|>, pm, [lhs, rhs]}
  end

  # `lhs |> Enum.map(mapper) |> Enum.into(empty_map)` => `lhs |> Map.new(mapper)`
  # or
  # `lhs |> Enum.map(mapper) |> Enum.into(collectable)` => `lhs |> Enum.into(collectable, mapper)
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., dm, [{_, _, [mod]}, :map]}, em, [mapper]},
           {{:., _, [{_, _, [:Enum]}, :into]} = into, _, [collectable]}
         )
       )
       when mod in @enum do
    rhs =
      case collectable do
        {{:., _, [{_, _, [mod]}, :new]}, _, []} when mod in @collectable ->
          {{:., dm, [{:__aliases__, dm, [mod]}, :new]}, em, [mapper]}

        {:%{}, _, []} ->
          {{:., dm, [{:__aliases__, dm, [:Map]}, :new]}, em, [mapper]}

        _ ->
          {into, m, [collectable]} = Style.set_line({into, em, [collectable]}, dm[:line])
          {into, m, [collectable, mapper]}
      end

    {:|>, pm, [lhs, rhs]}
  end

  # `lhs |> Enum.map(mapper) |> Map.new()` => `lhs |> Map.new(mapper)`
  defp fix_pipe(
         pipe_chain(
           pm,
           lhs,
           {{:., _, [{_, _, [enum]}, :map]}, em, [mapper]},
           {{:., _, [{_, _, [mod]}, :new]} = new, _, []}
         )
       )
       when mod in @collectable and enum in @enum do
    {:|>, pm, [lhs, {Style.set_line(new, em[:line]), em, [mapper]}]}
  end

  defp fix_pipe(node), do: node

  defp valid_pipe_start?({op, _, _}) when op in @special_ops, do: true
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
