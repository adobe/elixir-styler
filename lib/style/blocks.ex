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
  alias Styler.Zipper

  # case statement with exactly 2 `->` cases
  # rewrite to `if` if it's any of 3 trivial cases
  def run({{:case, _, [head, [{_, [{:->, _, [[lhs_a], a]}, {:->, _, [[lhs_b], b]}]}]]}, zm} = zipper, ctx) do
    case {lhs_a, lhs_b} do
      {{_, _, [true]}, {_, _, [false]}} -> if_ast(head, a, b, ctx, zm)
      {{_, _, [true]}, {:_, _, _}} -> if_ast(head, a, b, ctx, zm)
      {{_, _, [false]}, {_, _, [true]}} -> if_ast(head, b, a, ctx, zm)
      _ -> {:cont, zipper, ctx}
    end
  end

  # `Credo.Check.Refactor.CondStatements`
  def run({{:cond, _, [[{_, [{:->, _, [[head], a]}, {:->, _, [[{:__block__, _, [truthy]}], b]}]}]]}, m}, ctx)
      when is_atom(truthy) and truthy not in [nil, false],
      do: if_ast(head, a, b, ctx, m)

  # @TODO handle comments https://github.com/adobe/elixir-styler/issues/79
  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

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

      # drop singleton identity else clauses like `else foo -> foo end`
      elses =
        case elses do
          [{{_, _, [:else]}, [{:->, _, [[left], right]}]}] -> if nodes_equivalent?(left, right), do: [], else: elses
          _ -> elses
        end

      {reversed_clauses, do_body} =
        cond do
          # Put the postroll into the body
          Enum.any?(postroll) ->
            {_, do_body_meta, _} = do_body
            do_body = {:__block__, do_body_meta, Enum.reverse(postroll, [do_body])}
            {reversed_clauses, do_body}

          # Credo.Check.Refactor.RedundantWithClauseResult
          Enum.empty?(elses) and nodes_equivalent?(lhs, do_body) ->
            {rest, rhs}

          # no change
          true ->
            {reversed_clauses, do_body}
        end

      children = Enum.reverse(reversed_clauses, [[{do_block, do_body} | elses]])

      if Enum.any?(preroll),
        do: {:__block__, m, preroll ++ [{:with, m, children}]},
        else: {:with, m, children}
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

  defp if_ast({_, meta, _} = head, do_body, else_body, ctx, zipper_meta) do
    comments = ctx.comments
    line = meta[:line]
    do_body = Macro.update_meta(do_body, &Keyword.delete(&1, :end_of_expression))
    else_body = Macro.update_meta(else_body, &Keyword.delete(&1, :end_of_expression))

    max_do_line = max_line(do_body)
    max_else_line = max_line(else_body)
    end_line = max(max_do_line, max_else_line)

    # Change ast meta and comment lines to fit the `if` ast
    {do_block, else_block, comments} =
      if max_do_line >= max_else_line do
        # we're swapping the ordering of two blocks of code
        # and so must swap the lines of the ast & comments to keep comments where they belong!
        # the math is: move B up by the length of A, and move A down by the length of B plus one (for the else keyword)
        else_size = max_else_line - line
        do_size = max_do_line - max_else_line

        shifts = [
          # move comments in the `else_body` down by the size of the `do_body`
          {line..max_else_line, do_size},
          # move comments in `do_body` up by the size of the `else_body`
          {(max_else_line + 1)..max_do_line, -else_size}
        ]

        do_block = {{:__block__, [line: line], [:do]}, Style.shift_line(do_body, -else_size)}
        else_block = {{:__block__, [line: max_else_line], [:else]}, Style.shift_line(else_body, else_size + 1)}
        {do_block, else_block, Style.shift_comments(comments, shifts)}
      else
        # much simpler case -- just scootch things in the else down by 1 for the `else` keyword.
        do_block = {{:__block__, [line: line], [:do]}, do_body}
        else_block = Style.shift_line({{:__block__, [line: max_do_line], [:else]}, else_body}, 1)
        {do_block, else_block, Style.shift_comments(comments, max_do_line..max_else_line, 1)}
      end

    if_ast = style({:if, [do: [line: line], end: [line: end_line], line: line], [head, [do_block, else_block]]})
    {:cont, {if_ast, zipper_meta}, %{ctx | comments: comments}}
  end

  defp max_line(ast) do
    {_, max_line} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse(0, fn
        {{_, meta, _}, _} = z, max -> {z, max(meta[:line] || max, max)}
        z, max -> {z, max}
      end)

    max_line
  end
end
