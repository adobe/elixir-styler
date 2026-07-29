# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.SingleNode do
  @moduledoc """
  Simple 1-1 rewrites all crammed into one module to make for more efficient traversals

  Credo Rules addressed:

  * Credo.Check.Consistency.ParameterPatternMatching
  * Credo.Check.Readability.LargeNumbers
  * Credo.Check.Readability.ParenthesesOnZeroArityDefs
  * Credo.Check.Readability.PreferImplicitTry
  * Credo.Check.Readability.StringSigils
  * Credo.Check.Readability.WithSingleClause
  * Credo.Check.Refactor.CaseTrivialMatches
  * Credo.Check.Refactor.CondStatements
  * Credo.Check.Refactor.RedundantWithClauseResult
  * Credo.Check.Refactor.WithClauses
  """

  @behaviour Styler.Style

  @closing_delimiters [~s|"|, ")", "}", "|", "]", "'", ">", "/"]

  # `|> Timex.now()` => `|> Timex.now()`
  # skip over pipes into `Timex.now/1` so that we don't accidentally rewrite it as DateTime.utc_now/1
  def run({{:|>, _, [_, {{:., _, [{:__aliases__, _, [:Timex]}, :now]}, _, []}]}, _} = zipper, ctx),
    do: {:skip, zipper, ctx}

  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

  defp style({:assert, meta, [{:!=, _, [x, {:__block__, _, [nil]}]}]}), do: style({:assert, meta, [x]})
  # refute nilly -> assert
  defp style({:refute, meta, [{:is_nil, _, [x]}]}), do: style({:assert, meta, [x]})
  defp style({:refute, meta, [{:==, _, [x, {:__block__, _, [nil]}]}]}), do: style({:assert, meta, [x]})

  # negated comparisons
  defp style({:not, _, [{:==, m, xy}]}), do: {:!=, m, xy}
  defp style({:!, _, [{:==, m, xy}]}), do: {:!=, m, xy}

  # boolean ops and assert hurt my brain.
  # the lone exception is `==` (... for now) ((uh, and the exception to the exception is when it's `== nil`, above))
  defp style({:refute, meta, [{:!=, m, xy}]}), do: style({:assert, meta, [{:==, m, xy}]})
  defp style({:refute, meta, [{:!==, m, xy}]}), do: style({:assert, meta, [{:===, m, xy}]})
  defp style({:refute, meta, [{:<, m, xy}]}), do: style({:assert, meta, [{:>=, m, xy}]})
  defp style({:refute, meta, [{:<=, m, xy}]}), do: style({:assert, meta, [{:>, m, xy}]})
  defp style({:refute, meta, [{:>, m, xy}]}), do: style({:assert, meta, [{:<=, m, xy}]})
  defp style({:refute, meta, [{:>=, m, xy}]}), do: style({:assert, meta, [{:<, m, xy}]})

  for {a, inverted} <- [{:assert, :refute}, {:refute, :assert}] do
    # invert negations
    defp style({unquote(a), meta, [{n, _, [x]}]}) when n in [:!, :not], do: style({unquote(inverted), meta, [x]})

    # assert Enum.member? -> assert in
    defp style({unquote(a), meta, [{{:., _, [{:__aliases__, _, [:Enum]}, :member?]}, _, [enum, elem]}]}),
      do: {unquote(a), meta, [{:in, [line: meta[:line]], [elem, enum]}]}

    # assert Enum.find -> assert Enum.any?
    defp style({unquote(a), meta, [{{:., a, [{:__aliases__, b, [:Enum]}, :find]}, c, [enum, fun]}]}),
      do: style({unquote(a), meta, [{{:., a, [{:__aliases__, b, [:Enum]}, :any?]}, c, [enum, fun]}]})

    # Enum.any?(x, & &1 == y) => y in x
    defp style({unquote(a) = a, m, [{{:., _, [{:__aliases__, _, [:Enum]}, :any?]}, _, [y, fun]}]} = node) do
      case fun do
        # & &1 == x
        {:&, _, [{:==, _, [{:&, _, [1]}, x]}]} -> {a, m, [{:in, [line: m[:line]], [x, y]}]}
        # & x == &1
        {:&, _, [{:==, _, [x, {:&, _, [1]}]}]} -> {a, m, [{:in, [line: m[:line]], [x, y]}]}
        # fn var -> var == x
        {:fn, _, [{:->, _, [[{var, _, nil}], {:==, _, [{var, _, nil}, x]}]}]} -> {a, m, [{:in, [line: m[:line]], [x, y]}]}
        # fn var -> x == var
        {:fn, _, [{:->, _, [[{var, _, nil}], {:==, _, [x, {var, _, nil}]}]}]} -> {a, m, [{:in, [line: m[:line]], [x, y]}]}
        _ -> node
      end
    end
  end

  # rewrite double-quote strings with >= 4 escaped double-quotes as sigils
  defp style({:__block__, [{:delimiter, ~s|"|} | meta], [string]} = node) when is_binary(string) do
    # running a regex against every double-quote delimited string literal in a codebase doesn't have too much impact
    # on adobe's internal codebase, but perhaps other codebases have way more literals where this'd have an impact?
    if string =~ ~r/".*".*".*"/ do
      # choose whichever delimiter would require the least # of escapes,
      # ties being broken by our stylish ordering of delimiters (reflected in the 1-8 values)
      {closer, _} =
        string
        |> String.codepoints()
        |> Stream.filter(&(&1 in @closing_delimiters))
        |> Stream.concat(@closing_delimiters)
        |> Enum.frequencies()
        |> Enum.min_by(fn
          {"\"", count} -> {count, 1}
          {")", count} -> {count, 2}
          {"}", count} -> {count, 3}
          {"|", count} -> {count, 4}
          {"]", count} -> {count, 5}
          {"'", count} -> {count, 6}
          {">", count} -> {count, 7}
          {"/", count} -> {count, 8}
        end)

      delimiter =
        case closer do
          ")" -> "("
          "}" -> "{"
          "]" -> "["
          ">" -> "<"
          closer -> closer
        end

      {:sigil_s, [{:delimiter, delimiter} | meta], [{:<<>>, [line: meta[:line]], [string]}, []]}
    else
      node
    end
  end

  # Add / Correct `_` location in large numbers. Formatter handles large number (>5 digits) rewrites,
  # but doesn't rewrite typos like `100_000_0`, so it's worthwhile to have Styler do this
  #
  # `?-` isn't part of the number node - it's its parent - so all numbers are positive at this point
  defp style({:__block__, meta, [number]}) when is_number(number) and number >= 10_000 do
    # Checking here rather than in the anonymous function due to compiler bug https://github.com/elixir-lang/elixir/issues/10485
    integer? = is_integer(number)

    meta =
      Keyword.update!(meta, :token, fn
        "0x" <> _ = token ->
          token

        "0b" <> _ = token ->
          token

        "0o" <> _ = token ->
          token

        token when integer? ->
          delimit(token)

        # is float
        token ->
          [int_token, decimals] = String.split(token, ".")
          "#{delimit(int_token)}.#{decimals}"
      end)

    {:__block__, meta, [number]}
  end

  ## INEFFICIENT FUNCTION REWRITES
  # Keep in mind when rewriting a `/n::pos_integer` arity function here that it should also be added
  # to the pipes rewriting rules, where it will appear as `/n-1`

  # Enum.into(enum, empty_map[, ...]) => Map.new(enum[, ...])
  defp style({{:., _, [{:__aliases__, _, [:Enum]}, :into]} = into, m, [enum, collectable | rest]} = node) do
    if replacement = replace_into(into, collectable, rest), do: {replacement, m, [enum | rest]}, else: node
  end

  # lhs |> Enum.into(%{}, ...) => lhs |> Map.new(...)
  defp style({:|>, meta, [lhs, {{:., _, [{_, _, [:Enum]}, :into]} = into, m, [collectable | rest]}]} = node) do
    if replacement = replace_into(into, collectable, rest), do: {:|>, meta, [lhs, {replacement, m, rest}]}, else: node
  end

  for m <- [:Map, :Keyword] do
    # lhs |> Map.merge(%{key: value}) => lhs |> Map.put(key, value)
    defp style({:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [{:%{}, _, [{key, value}]}]}]}),
      do: {:|>, pm, [lhs, {{:., dm, [module, :put]}, m, [key, value]}]}

    # lhs |> Map.merge(key: value) => lhs |> Map.put(:key, value)
    defp style({:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [[{key, value}]]}]}),
      do: {:|>, pm, [lhs, {{:., dm, [module, :put]}, m, [key, value]}]}

    # lhs |> Map.merge([key: value]) => lhs |> Map.put(:key, value)
    defp style(
           {:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [{:__block__, _, [[{key, value}]]}]}]}
         ), do: {:|>, pm, [lhs, {{:., dm, [module, :put]}, m, [key, value]}]}

    # Map.merge(foo, %{one_key: :bar}) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, {:%{}, _, [{key, value}]}]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}

    # Map.merge(foo, one_key: :bar) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, [{key, value}]]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}

    # Map.merge(foo, [one_key: :bar]) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, {:__block__, _, [[{key, value}]]}]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}

    # (lhs |>) Map.drop([key]) => Map.delete(key)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :drop]}, m, [{:__block__, _, [[{op, _, _} = key]]}]})
         when op != :|, do: {{:., dm, [module, :delete]}, m, [key]}

    # Map.drop(foo, [one_key]) => Map.delete(foo, one_key)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :drop]}, m, [lhs, {:__block__, _, [[{op, _, _} = key]]}]})
         when op != :|, do: {{:., dm, [module, :delete]}, m, [lhs, key]}
  end

  # Timex.now() => DateTime.utc_now()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, []}),
    do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :utc_now]}, funm, []}

  # DateTime.shift([dt, ]second: 24 * 60 * 60[, calendar]) => DateTime.shift([dt, ]day: 1[, calendar])
  defp style({{:., dm, [{:__aliases__, am, [:DateTime]}, :shift]}, funm, args}) do
    # rather than go through all the different args we can get due to pipes, not pipes, shift/2, shift/3
    # we can just be cheap and look for a list of pairs to shrink.
    args =
      Enum.map(args, fn
        # Keyword list args
        [{_, _} | _] = pairs -> Enum.map(pairs, &shrink_duration/1)
        # literal list args
        {:__block__, m, [[{_, _} | _] = pairs]} -> {:__block__, m, [Enum.map(pairs, &shrink_duration/1)]}
        other -> other
      end)

    {{:., dm, [{:__aliases__, am, [:DateTime]}, :shift]}, funm, args}
  end

  # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :lt => {DateTime,NaiveDateTime,Time,Date}.before?(a, b)
  # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :gt => {DateTime,NaiveDateTime,Time,Date}.after?(a, b)
  defp style({:==, _, [{{:., dm, [{:__aliases__, am, [mod]}, :compare]}, funm, args}, {:__block__, _, [result]}]})
       when mod in ~w[DateTime NaiveDateTime Time Date]a and result in [:lt, :gt] do
    fun = if result == :lt, do: :before?, else: :after?
    {{:., dm, [{:__aliases__, am, [mod]}, fun]}, funm, args}
  end

  # Remove parens from 0 arity funs (Credo.Check.Readability.ParenthesesOnZeroArityDefs)
  defp style({def, dm, [{fun, funm, []} | rest]}) when def in ~w(def defp)a and is_atom(fun),
    do: style({def, dm, [{fun, Keyword.delete(funm, :closing), nil} | rest]})

  # `Credo.Check.Readability.PreferImplicitTry`
  defp style({def, dm, [head, [{_, {:try, _, [try_children]}}]]}) when def in ~w(def defp)a,
    do: style({def, dm, [head, try_children]})

  defp style({def, dm, [{fun, funm, params} | rest]}) when def in ~w(def defp)a,
    do: {def, dm, [{fun, funm, put_matches_on_right(params)} | rest]}

  # `Enum.reverse(foo) ++ bar` => `Enum.reverse(foo, bar)`
  defp style({:++, _, [{{:., _, [{_, _, [:Enum]}, :reverse]} = reverse, r_meta, [lhs]}, rhs]}),
    do: {reverse, r_meta, [lhs, rhs]}

  # ARROW REWRITES
  # `with`, `for` left arrow - if only we could write something this trivial for `->`!
  defp style({:<-, cm, [lhs, rhs]}), do: {:<-, cm, [put_matches_on_right(lhs), rhs]}
  # there's complexity to `:->` due to `cond` also utilizing the symbol but with different semantics.
  # thus, we have to have a clause for each place that `:->` can show up
  # `with` elses
  defp style({{:__block__, _, [:else]} = else_, arrows}), do: {else_, rewrite_arrows(arrows)}
  defp style({:case, cm, [head, [{do_, arrows}]]}), do: {:case, cm, [head, [{do_, rewrite_arrows(arrows)}]]}
  defp style({:fn, m, arrows}), do: {:fn, m, rewrite_arrows(arrows)}

  defp style({:to_timeout, m, [[_ | _] = args]}), do: {:to_timeout, m, [Enum.map(args, &shrink_duration/1)]}

  defp style(node), do: node

  defp duration_step(:day), do: {:day, 7, :week}
  defp duration_step(:days), do: {:day, 7, :week}
  defp duration_step(:hour), do: {:hour, 24, :day}
  defp duration_step(:hours), do: {:hour, 24, :day}
  defp duration_step(:millisecond), do: {:millisecond, 1000, :second}
  defp duration_step(:milliseconds), do: {:millisecond, 1000, :second}
  defp duration_step(:minute), do: {:minute, 60, :hour}
  defp duration_step(:minutes), do: {:minute, 60, :hour}
  defp duration_step(:second), do: {:second, 60, :minute}
  defp duration_step(:seconds), do: {:second, 60, :minute}
  defp duration_step(:week), do: {:week, :"$no_next_step", nil}
  defp duration_step(:weeks), do: {:week, :"$no_next_step", nil}
  defp duration_step(unit), do: {unit, :"$no_next_step", nil}

  # does the heavy work of recursively stepping the integer/unit pair up, eg
  # second: 86_400 -> day: 1
  defp shrink_unit(int, unit) when is_atom(unit), do: shrink_unit(int, duration_step(unit))

  defp shrink_unit(int, {_, step, next_unit}) when int != 0 and rem(int, step) == 0,
    do: int |> div(step) |> shrink_unit(duration_step(next_unit))

  defp shrink_unit(int, {unit, _, _}), do: {int, unit}
  # 1. convert plurals to singulars (`minutes` -> `minute`) to cover erlang `to_timeout` conversions
  # 2. shrinks values, eg `minute: 5 * 60` -> `hour: 5`; `minute: 60` -> `hour: 1`
  defp shrink_duration({{:__block__, m, [unit]}, value}) do
    # with step-ups, there's no need for multiplication in shifts (i think??)
    # # so we reduce all literal multiplication that we can
    computed =
      Macro.postwalk(value, fn
        {:__block__, _, [a]} when is_integer(a) -> a
        {:*, _, [a, b]} when is_integer(a) and is_integer(b) -> a * b
        {:*, m, [{:*, _, [x, a]}, b]} when is_integer(a) and is_integer(b) -> {:*, m, [x, a * b]}
        {:*, m, [{:*, _, [a, x]}, b]} when is_integer(a) and is_integer(b) -> {:*, m, [x, a * b]}
        {:-, _, [a]} when is_integer(a) -> -a
        {:*, _, [a, b]} = node when is_integer(a) or is_integer(b) -> node
        other -> other
      end)

    line = m[:line]

    case computed do
      a when is_integer(a) ->
        {a, unit} = shrink_unit(a, unit)
        {{:__block__, m, [unit]}, int_to_literal(a, line)}

      {:*, mm, [x, a]} when is_integer(a) ->
        {a, unit} = shrink_unit(a, unit)
        value = if a == 1, do: x, else: {:*, mm, [x, int_to_literal(a, line)]}
        {{:__block__, m, [unit]}, value}

      {:*, mm, [a, x]} when is_integer(a) ->
        {a, unit} = shrink_unit(a, unit)
        value = if a == 1, do: x, else: {:*, mm, [int_to_literal(a, line), x]}
        {{:__block__, m, [unit]}, value}

      # couldn't shrink! identity it.
      _ ->
        {{:__block__, m, [unit]}, value}
    end
  end

  defp shrink_duration(other), do: other

  defp int_to_literal(int, line) when int >= 0,
    do: {:__block__, [line: line, token: int |> to_string() |> delimit()], [int]}

  defp int_to_literal(negative, line), do: {:-, [line: line], [int_to_literal(-1 * negative, line)]}

  defp replace_into({:., dm, [{_, am, _} = enum, _]}, collectable, rest) do
    case collectable do
      {{:., _, [{_, _, [mod]}, :new]}, _, []} when mod in ~w(Map Keyword MapSet)a ->
        {:., dm, [{:__aliases__, am, [mod]}, :new]}

      {:%{}, _, []} ->
        {:., dm, [{:__aliases__, am, [:Map]}, :new]}

      {:__block__, _, [[]]} ->
        if Enum.empty?(rest), do: {:., dm, [enum, :to_list]}, else: {:., dm, [enum, :map]}

      _ ->
        nil
    end
  end

  defp rewrite_arrows(arrows) when is_list(arrows),
    do: Enum.map(arrows, fn {:->, m, [lhs, rhs]} -> {:->, m, [put_matches_on_right(lhs), rhs]} end)

  defp rewrite_arrows(macros_or_something_crazy_oh_no_abooort), do: macros_or_something_crazy_oh_no_abooort

  defp put_matches_on_right(ast) do
    Macro.prewalk(ast, fn
      # `_ = var ->` => `var ->`
      {:=, _, [{:_, _, nil}, var]} -> var
      # `var = _ ->` => `var ->`
      {:=, _, [var, {:_, _, nil}]} -> var
      # `var = *match*`  -> `*match -> var`
      {:=, m, [{_, _, nil} = var, match]} -> {:=, m, [match, var]}
      node -> node
    end)
  end

  defp delimit(token), do: token |> String.to_charlist() |> remove_underscores([]) |> add_underscores([])

  defp remove_underscores([?_ | rest], acc), do: remove_underscores(rest, acc)
  defp remove_underscores([digit | rest], acc), do: remove_underscores(rest, [digit | acc])
  defp remove_underscores([], reversed_list), do: reversed_list

  defp add_underscores([a, b, c, d | rest], acc), do: add_underscores([d | rest], [?_, c, b, a | acc])
  defp add_underscores(reversed_list, acc), do: reversed_list |> Enum.reverse(acc) |> to_string()
end
