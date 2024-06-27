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
          {~s|"|, count} -> {count, 1}
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

    # Map.merge(foo, %{one_key: :bar}) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, {:%{}, _, [{key, value}]}]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}

    # Map.merge(foo, one_key: :bar) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, [{key, value}]]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}

    # (lhs |>) Map.drop([key]) => Map.delete(key)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :drop]}, m, [{:__block__, _, [[{op, _, _} = key]]}]})
         when op != :|,
         do: {{:., dm, [module, :delete]}, m, [key]}

    # Map.drop(foo, [one_key]) => Map.delete(foo, one_key)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :drop]}, m, [lhs, {:__block__, _, [[{op, _, _} = key]]}]})
         when op != :|,
         do: {{:., dm, [module, :delete]}, m, [lhs, key]}
  end

  # Timex.now() => DateTime.utc_now()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, []}),
    do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :utc_now]}, funm, []}

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

  defp style({def, dm, [{fun, funm, params} | rest]}) when def in ~w(def defp)a do
    {def, dm, [{fun, funm, put_matches_on_right(params)} | rest]}
  end

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

  defp style(node), do: node

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

  defp delimit(token) do
    chars = String.to_charlist(token)

    result =
      case Enum.reverse(chars) do
        [hundredth, tenth, ?_ | rest] when is_integer(tenth) and is_integer(hundredth) ->
          delimited = rest |> Enum.reverse() |> fix_underscores()

          delimited ++ [?_, tenth, hundredth]

        _other_num ->
          fix_underscores(chars)
      end

    to_string(result)
  end

  defp fix_underscores(num_tokens) do
    num_tokens
    |> remove_underscores([])
    |> add_underscores([])
  end

  defp remove_underscores([?_ | rest], acc), do: remove_underscores(rest, acc)
  defp remove_underscores([digit | rest], acc), do: remove_underscores(rest, [digit | acc])
  defp remove_underscores([], reversed_list), do: reversed_list

  defp add_underscores([a, b, c, d | rest], acc), do: add_underscores([d | rest], [?_, c, b, a | acc])
  defp add_underscores(reversed_list, acc), do: Enum.reverse(reversed_list, acc)
end
