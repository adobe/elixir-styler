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
  * Credo.Check.Refactor.CaseTrivialMatches
  """

  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

  defmacrop trivial_case(head, a, a_body, b, b_body) do
    quote do
      {:case, _,
       [
         unquote(head),
         [
           {_,
            [
              {:->, _, [[unquote(a)], unquote(a_body)]},
              {:->, _, [[unquote(b)], unquote(b_body)]}
            ]}
         ]
       ]}
    end
  end

  # Our use of the `literal_encoder` option of `Code.string_to_quoted_with_comments!/2` creates
  # invalid charlists literal AST nodes from `'foo'`. this rewrites them to use the `~c` sigil
  # 'foo' => ~c"foo".
  defp style({:__block__, meta, [[int | _] = chars]} = node) when is_integer(int) do
    if meta[:delimiter] == "'" do
      new_meta = Keyword.put(meta, :delimiter, "\"")
      {:sigil_c, new_meta, [{:<<>>, [line: meta[:line]], [List.to_string(chars)]}, []]}
    else
      node
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

  defp style({{:., dm, [{:__aliases__, am, [:Enum]}, :into]}, funm, [enum, collectable | rest]} = node) do
    if Style.empty_map?(collectable), do: {{:., dm, [{:__aliases__, am, [:Map]}, :new]}, funm, [enum | rest]}, else: node
  end

  # Logger.warn -> Logger.warning
  defp style({{:., dm, [{:__aliases__, am, [:Logger]}, :warn]}, funm, args}),
    do: {{:., dm, [{:__aliases__, am, [:Logger]}, :warning]}, funm, args}

  # Timex.today() => DateTime.utc_today()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :today]}, funm, []}),
    do: {{:., dm, [{:__aliases__, am, [:Date]}, :utc_today]}, funm, []}

  # Timex.now() => DateTime.utc_now()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, []}),
    do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :utc_now]}, funm, []}

  # Timex.now("Europe/London") => DateTime.now!()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, [tz]}),
    do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :now!]}, funm, [tz]}

  if Version.match?(System.version(), ">= 1.15.0-dev") do
    # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :lt -> {DateTime,NaiveDateTime,Time,Date}.before?(a, b)
    # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :gt -> {DateTime,NaiveDateTime,Time,Date}.after?(a, b)
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

  defp style(trivial_case(head, {:__block__, _, [true]}, do_body, {:__block__, _, [false]}, else_body)),
    do: if_ast(head, do_body, else_body)

  defp style(trivial_case(head, {:__block__, _, [false]}, else_body, {:__block__, _, [true]}, do_body)),
    do: if_ast(head, do_body, else_body)

  defp style(trivial_case(head, {:__block__, _, [true]}, do_body, {:_, _, _}, else_body)),
    do: if_ast(head, do_body, else_body)

  defp style({:case, cm, [head, [{do_block, arrows}]]}), do: {:case, cm, [head, [{do_block, r_align_matches(arrows)}]]}

  defp style({:fn, m, arrows}), do: {:fn, m, r_align_matches(arrows)}

  defp style(node), do: node

  defp r_align_matches(arrows),
    do: Enum.map(arrows, fn {:->, m, [lhs, rhs]} -> {:->, m, [put_matches_on_right(lhs), rhs]} end)

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

  # don't write an else clause if it's `false -> nil`
  defp if_ast(head, do_body, {:__block__, _, [nil]}), do: {:if, [do: []], [head, [{{:__block__, [], [:do]}, do_body}]]}

  defp if_ast(head, do_body, else_body),
    do: {:if, [do: [], end: []], [head, [{{:__block__, [], [:do]}, do_body}, {{:__block__, [], [:else]}, else_body}]]}

  defp delimit(token), do: token |> String.to_charlist() |> remove_underscores([]) |> add_underscores([])

  defp remove_underscores([?_ | rest], acc), do: remove_underscores(rest, acc)
  defp remove_underscores([digit | rest], acc), do: remove_underscores(rest, [digit | acc])
  defp remove_underscores([], reversed_list), do: reversed_list

  defp add_underscores([a, b, c, d | rest], acc), do: add_underscores([d | rest], [?_, c, b, a | acc])
  defp add_underscores(reversed_list, acc), do: reversed_list |> Enum.reverse(acc) |> to_string()
end
