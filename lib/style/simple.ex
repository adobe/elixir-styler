# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Simple do
  @moduledoc """
  Simple 1-1 rewrites all crammed into one module to make for more efficient traversals

  Credo Rules addressed:

  * Credo.Check.Readability.LargeNumbers
      Formatter handles large number (>5 digits) rewrites, but doesn't rewrite typos like `100_000_0`, so it's worthwhile to have styler do this
  * Credo.Check.Readability.ParenthesesOnZeroArityDefs
  * Credo.Check.Refactor.CaseTrivialMatches
  """

  @behaviour Styler.Style

  alias Styler.Zipper

  # `?-` isn't part of the number node - it's its parent - so all numbers are positive at this point
  def run({{:__block__, meta, [number]}, _} = zipper, ctx) when is_number(number) and number >= 10_000 do
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

    {:skip, Zipper.replace(zipper, {:__block__, meta, [number]}), ctx}
  end

  def run({{def, dm, [{fun, funm, []} | rest]}, _} = zipper, ctx) when def in ~w(def defp)a do
    {:cont, Zipper.replace(zipper, {def, dm, [{fun, funm, nil} | rest]}), ctx}
  end

  # `Enum.reverse(foo) ++ bar` => `Enum.reverse(foo, bar)`
  def run({{:++, _, [{{:., _, [{_, _, [:Enum]}, :reverse]} = reverse, r_meta, [lhs]}, rhs]}, _} = zipper, ctx) do
    {:cont, Zipper.replace(zipper, {reverse, r_meta, [lhs, rhs]}), ctx}
  end

  def run(
        {{:case, _,
          [
            head,
            [{_, [{:->, _, [[{:__block__, _, [true]}], do_body]}, {:->, _, [[{:__block__, _, [false]}], else_body]}]}]
          ]}, _} = zipper,
        ctx
      ) do
    {:cont, Zipper.replace(zipper, if_ast(head, do_body, else_body)), ctx}
  end

  def run(
        {{:case, _, [head, [{_, [{:->, _, [[{:__block__, _, [true]}], do_body]}, {:->, _, [[{:_, _, _}], else_body]}]}]]},
         _} = zipper,
        ctx
      ) do
    {:cont, Zipper.replace(zipper, if_ast(head, do_body, else_body)), ctx}
  end

  def run(
        {{:case, _,
          [
            head,
            [{_, [{:->, _, [[{:__block__, _, [false]}], else_body]}, {:->, _, [[{:__block__, _, [true]}], do_body]}]}]
          ]}, _} = zipper,
        ctx
      ) do
    {:cont, Zipper.replace(zipper, if_ast(head, do_body, else_body)), ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

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
