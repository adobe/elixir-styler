# Copyright 2023 Adobe. All rights reserved.
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
  * Credo.Check.Readability.WithSingleClause
  * Credo.Check.Refactor.CaseTrivialMatches
  * Credo.Check.Refactor.CondStatements
  * Credo.Check.Refactor.RedundantWithClauseResult
  * Credo.Check.Refactor.WithClauses
  """

  @behaviour Styler.Style

  alias Styler.Zipper

  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

  # as of 1.15, elixir's formatter takes care of this for us.
  if Version.match?(System.version(), "< 1.15.0-dev") do
    # 'charlist' => ~c"charlist"
    defp style({:__block__, meta, [chars]} = node) when is_list(chars) do
      if meta[:delimiter] == "'",
        do: {:sigil_c, Keyword.put(meta, :delimiter, "\""), [{:<<>>, [line: meta[:line]], [List.to_string(chars)]}, []]},
        else: node
    end
  end

  # Add / Correct `_` location in large numbers. Formatter handles large number (>5 digits) rewrites,
  # but doesn't rewrite typos like `100_000_0`, so it's worthwhile to have Styler do this
  #
  # `?-` isn't part of the number node - it's its parent - so all numbers are positive at this point
  defp style({:__block__, meta, [number]}) when is_number(number) and number >= 10_000 do
    # Checking here rather than in the anon function due to compiler bug https://github.com/elixir-lang/elixir/issues/10485
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
  defp style({{:., dm, [{:__aliases__, _, [:Enum]}, :into]}, funm, [enum, collectable | rest]} = node) do
    new_collectable =
      case collectable do
        {{:., _, [{_, _, [mod]}, :new]}, _, []} when mod in ~w(Map Keyword MapSet)a ->
          {:., dm, [{:__aliases__, dm, [mod]}, :new]}

        {:%{}, _, []} ->
          {:., dm, [{:__aliases__, dm, [:Map]}, :new]}

        _ ->
          nil
      end

    if new_collectable, do: {new_collectable, funm, [enum | rest]}, else: node
  end

  for mod <- [:Map, :Keyword] do
    # Map.merge(foo, %{one_key: :bar}) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(mod)]} = module, :merge]}, m, [lhs, {:%{}, _, [{key, value}]}]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}

    # Map.merge(foo, one_key: :bar) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(mod)]} = module, :merge]}, m, [lhs, [{key, value}]]}),
      do: {{:., dm, [module, :put]}, m, [lhs, key, value]}
  end

  # Timex.now() => DateTime.utc_now()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, []}),
    do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :utc_now]}, funm, []}

  # Timex.now(tz) => DateTime.now!(tz)
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, [tz]}),
    do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :now!]}, funm, [tz]}

  if Version.match?(System.version(), ">= 1.15.0-dev") do
    # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :lt => {DateTime,NaiveDateTime,Time,Date}.before?(a, b)
    # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :gt => {DateTime,NaiveDateTime,Time,Date}.after?(a, b)
    defp style({:==, _, [{{:., dm, [{:__aliases__, am, [mod]}, :compare]}, funm, args}, {:__block__, _, [result]}]})
         when mod in ~w[DateTime NaiveDateTime Time Date]a and result in [:lt, :gt] do
      fun = if result == :lt, do: :before?, else: :after?
      {{:., dm, [{:__aliases__, am, [mod]}, fun]}, funm, args}
    end
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

  defp style(node), do: node

  defp rewrite_arrows(arrows) when is_list(arrows),
    do: Enum.map(arrows, fn {:->, m, [lhs, rhs]} -> {:->, m, [put_matches_on_right(lhs), rhs]} end)

  defp rewrite_arrows(macros_or_something_crazy_oh_no_abooort), do: macros_or_something_crazy_oh_no_abooort

  defp put_matches_on_right(ast) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse(fn
      # `_ = var ->` => `var ->`
      {{:=, _, [{:_, _, nil}, var]}, _} = zipper -> Zipper.replace(zipper, var)
      # `var = _ ->` => `var ->`
      {{:=, _, [var, {:_, _, nil}]}, _} = zipper -> Zipper.replace(zipper, var)
      # `var = *match*`  -> `*match -> var`
      {{:=, m, [{_, _, nil} = var, match]}, _} = zipper -> Zipper.replace(zipper, {:=, m, [match, var]})
      zipper -> zipper
    end)
    |> Zipper.node()
  end

  defp delimit(token), do: token |> String.to_charlist() |> remove_underscores([]) |> add_underscores([])

  defp remove_underscores([?_ | rest], acc), do: remove_underscores(rest, acc)
  defp remove_underscores([digit | rest], acc), do: remove_underscores(rest, [digit | acc])
  defp remove_underscores([], reversed_list), do: reversed_list

  defp add_underscores([a, b, c, d | rest], acc), do: add_underscores([d | rest], [?_, c, b, a | acc])
  defp add_underscores(reversed_list, acc), do: reversed_list |> Enum.reverse(acc) |> to_string()
end
