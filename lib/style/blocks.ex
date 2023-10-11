# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Blocks do
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

  alias Styler.Style

  # @TODO handle comments https://github.com/adobe/elixir-styler/issues/79
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

  defp style(trivial_case(head, {_, _, [true]}, do_, {_, _, [false]}, else_)), do: styled_if(head, do_, else_)
  defp style(trivial_case(head, {_, _, [false]}, else_, {_, _, [true]}, do_)), do: styled_if(head, do_, else_)
  defp style(trivial_case(head, {_, _, [true]}, do_, {:_, _, _}, else_)), do: styled_if(head, do_, else_)

  # `Credo.Check.Refactor.CondStatements`
  # This also detects strings and lists...
  defp style({:cond, _, [[{_, [{:->, _, [[expr], do_body]}, {:->, _, [[{:__block__, _, [truthy]}], else_body]}]}]]})
       when is_atom(truthy) and truthy not in [nil, false] do
    styled_if(expr, do_body, else_body)
  end

  # Credo.Check.Readability.WithSingleClause
  # rewrite `with success <- single_statement do body else ...elses end`
  # to `case single_statement do success -> body; ...elses end`
  defp style({:with, m, [{:<-, am, [success, single_statement]}, [body, elses]]}) do
    {{:__block__, do_meta, [:do]}, body} = body
    {{:__block__, _else_meta, [:else]}, elses} = elses
    clauses = [{{:__block__, am, [:do]}, [{:->, do_meta, [[success], body]} | elses]}]
    style({:case, m, [single_statement, clauses]})
  end

  # Credo.Check.Refactor.WithClauses
  # Credo.Check.Refactor.RedundantWithClauseResult
  defp style({:with, m, children} = with) when is_list(children) do
    if Enum.any?(children, &left_arrow?/1) do
      {preroll, children} = Enum.split_while(children, &(not left_arrow?(&1)))
      # the do/else keyword macro of the with statement is the last element of the list
      [[{do_block, do_body} | elses] | reversed_clauses] = Enum.reverse(children)
      {postroll, reversed_clauses} = Enum.split_while(reversed_clauses, &(not left_arrow?(&1)))
      [{:<-, _, [lhs, rhs]} = _final_clause | rest] = reversed_clauses

      # Credo.Check.Refactor.RedundantWithClauseResult
      rewrite_body? = Enum.empty?(postroll) and Enum.empty?(elses) and nodes_equivalent?(lhs, do_body)
      {_, do_body_meta, _} = do_body

      {reversed_clauses, do_body} =
        if rewrite_body?,
          do: {rest, [rhs]},
          else: {reversed_clauses, Enum.reverse(postroll, [do_body])}

      do_else = [{do_block, {:__block__, do_body_meta, do_body}} | elses]
      children = Enum.reverse(reversed_clauses, [do_else])

      # only rewrite if it needs rewriting!
      cond do
        Enum.any?(preroll) ->
          {:__block__, m, preroll ++ [{:with, m, children}]}

        rewrite_body? or Enum.any?(postroll) ->
          {:with, m, children}

        true ->
          with
      end
    else
      # maybe this isn't a with statement - could be a function named `with`
      # or it's just a with statement with no arrows, but that's too saddening to imagine
      with
    end
  end

  # Credo.Check.Refactor.UnlessWithElse
  defp style({:unless, m, [{_, hm, _} = head, [_, _] = do_else]}), do: style({:if, m, [{:!, hm, [head]}, do_else]})

  # Credo.Check.Refactor.NegatedConditionsInUnless
  defp style({:unless, m, [{negator, _, [expr]}, [{do_, do_body}]]}) when negator in [:!, :not],
    do: style({:if, m, [expr, [{do_, do_body}]]})

  # Credo.Check.Refactor.NegatedConditionsWithElse
  defp style({:if, m, [{negator, _, [expr]}, [{do_, do_body}, {else_, else_body}]]}) when negator in [:!, :not],
    do: style({:if, m, [expr, [{do_, else_body}, {else_, do_body}]]})

  defp style({:if, m, [head, [do_block, {_, {:__block__, _, [nil]}}]]}), do: {:if, m, [head, [do_block]]}

  defp style(node), do: node

  defp left_arrow?({:<-, _, _}), do: true
  defp left_arrow?(_), do: false

  defp nodes_equivalent?(a, b) do
    # compare nodes without metadata
    Style.update_all_meta(a, fn _ -> nil end) == Style.update_all_meta(b, fn _ -> nil end)
  end

  defp styled_if(head, do_body, else_body) do
    {_, meta, _} = head
    line = meta[:line]
    # @TODO figure out appropriate line meta for `else` and `if->end->line`
    children = [head, [{{:__block__, [line: line], [:do]}, do_body}, {{:__block__, [], [:else]}, else_body}]]
    style({:if, [line: line, do: [line: line], end: []], children})
  end
end
