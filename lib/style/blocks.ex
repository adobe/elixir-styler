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

  defguardp is_negator(n) when n in [:!, :not]

  # case statement with exactly 2 `->` cases
  # rewrite to `if` if it's any of 3 trivial cases
  def run({{:case, _, [head, [{_, [{:->, _, [[lhs_a], a]}, {:->, _, [[lhs_b], b]}]}]]}, _} = zipper, ctx) do
    case {lhs_a, lhs_b} do
      {{_, _, [true]}, {_, _, [false]}} -> if_ast(zipper, head, a, b, ctx)
      {{_, _, [true]}, {:_, _, _}} -> if_ast(zipper, head, a, b, ctx)
      {{_, _, [false]}, {_, _, [true]}} -> if_ast(zipper, head, b, a, ctx)
      _ -> {:cont, zipper, ctx}
    end
  end

  # Credo.Check.Refactor.CondStatements
  def run({{:cond, _, [[{_, [{:->, _, [[head], a]}, {:->, _, [[{:__block__, _, [truthy]}], b]}]}]]}, _} = zipper, ctx)
      when is_atom(truthy) and truthy not in [nil, false],
      do: if_ast(zipper, head, a, b, ctx)

  # Credo.Check.Readability.WithSingleClause
  # rewrite `with success <- single_statement do body else ...elses end`
  # to `case single_statement do success -> body; ...elses end`
  def run({{:with, m, [{:<-, am, [success, single_statement]}, [body, elses]]}, zm}, ctx) do
    {{:__block__, do_meta, [:do]}, body} = body
    {{:__block__, _else_meta, [:else]}, elses} = elses
    clauses = [{{:__block__, am, [:do]}, [{:->, do_meta, [[success], body]} | elses]}]
    # recurse in case this new case should be rewritten to a `if`, etc
    run({{:case, m, [single_statement, clauses]}, zm}, ctx)
  end

  # Credo.Check.Refactor.WithClauses
  def run({{:with, with_meta, children}, _} = zipper, ctx) when is_list(children) do
    if Enum.any?(children, &left_arrow?/1) do
      {preroll, children} =
        children
        |> Enum.map(fn
          # `_ <- rhs` => `rhs`
          {:<-, _, [{:_, _, _}, rhs]} -> rhs
          # `lhs <- rhs` => `lhs = rhs`
          {:<-, m, [{atom, _, nil} = lhs, rhs]} when is_atom(atom) -> {:=, m, [lhs, rhs]}
          child -> child
        end)
        |> Enum.split_while(&(not left_arrow?(&1)))

      # after rewriting `x <- y()` to `x = y()` there are no more arrows.
      # this never should've been a with statement at all! we can just replace it with assignments
      if Enum.empty?(children) do
        {:cont, replace_with_statement(zipper, preroll), ctx}
      else
        [[{{_, do_meta, _} = do_block, do_body} | elses] | reversed_clauses] = Enum.reverse(children)
        {postroll, reversed_clauses} = Enum.split_while(reversed_clauses, &(not left_arrow?(&1)))
        [{:<-, final_clause_meta, [lhs, rhs]} = _final_clause | rest] = reversed_clauses

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
              {node, do_body_meta, do_children} = do_body
              do_children = if node == :__block__, do: do_children, else: [do_body]
              do_body = {:__block__, Keyword.take(do_body_meta, [:line]), Enum.reverse(postroll, do_children)}
              {reversed_clauses, do_body}

            # Credo.Check.Refactor.RedundantWithClauseResult
            Enum.empty?(elses) and nodes_equivalent?(lhs, do_body) ->
              {rest, rhs}

            # no change
            true ->
              {reversed_clauses, do_body}
          end

        do_line = do_meta[:line]
        final_clause_line = final_clause_meta[:line]

        do_line =
          cond do
            do_meta[:format] == :keyword && final_clause_line + 1 >= do_line -> do_line
            do_meta[:format] == :keyword -> final_clause_line + 1
            true -> final_clause_line
          end

        do_block = Macro.update_meta(do_block, &Keyword.put(&1, :line, do_line))
        # disable keyword `, do:` since there will be multiple statements in the body
        with_meta =
          if Enum.any?(postroll),
            do: Keyword.merge(with_meta, do: [line: with_meta[:line]], end: [line: max_line(children) + 1]),
            else: with_meta

        with_children = Enum.reverse(reversed_clauses, [[{do_block, do_body} | elses]])
        zipper = Zipper.replace(zipper, {:with, with_meta, with_children})

        # recurse if the # of `<-` have changed (this `with` could now be eligible for a `case` rewrite)
        cond do
          Enum.any?(preroll) ->
            # put the preroll before the with statement in either a block we create or the existing parent block
            zipper
            |> Style.find_nearest_block()
            |> Zipper.prepend_siblings(preroll)
            |> run(ctx)

          Enum.any?(postroll) ->
            # both of these changed the # of `<-`, so we should have another look at this with statement
            run(zipper, ctx)

          Enum.empty?(reversed_clauses) ->
            # oops! RedundantWithClauseResult removed the final arrow in this. no more need for a with statement!
            {:cont, replace_with_statement(zipper, with_children), ctx}

          true ->
            # of clauess didn't change, so don't reecurse or we'll loop FOREEEVEERR
            {:cont, zipper, ctx}
        end
      end
    else
      # maybe this isn't a with statement - could be a function named `with`
      # or it's just a with statement with no arrows, but that's too saddening to imagine
      {:cont, zipper, ctx}
    end
  end

  def run({{:unless, m, children}, _} = zipper, ctx) do
    case children do
      # Credo.Check.Refactor.UnlessWithElse
      [{_, hm, _} = head, [_, _] = do_else] ->
        zipper |> Zipper.replace({:if, m, [{:!, hm, [head]}, do_else]}) |> run(ctx)

      # Credo.Check.Refactor.NegatedConditionsInUnless
      [{negator, _, [expr]}, [{do_, do_body}]] when is_negator(negator) ->
        zipper |> Zipper.replace({:if, m, [expr, [{do_, do_body}]]}) |> run(ctx)

      _ ->
        {:cont, zipper, ctx}
    end
  end

  def run({{:if, m, children}, _} = zipper, ctx) do
    case children do
      # Credo.Check.Refactor.NegatedConditionsWithElse
      [{negator, _, [expr]}, [{do_, do_body}, {else_, else_body}]] when is_negator(negator) ->
        zipper |> Zipper.replace({:if, m, [expr, [{do_, else_body}, {else_, do_body}]]}) |> run(ctx)

      # if not x, do: y => unless x, do: y
      [{negator, _, [expr]}, [do_block]] when is_negator(negator) ->
        zipper |> Zipper.replace({:unless, m, [expr, [do_block]]}) |> run(ctx)

      # drop `else: nil`
      [head, [do_block, {_, {:__block__, _, [nil]}}]] ->
        {:cont, Zipper.replace(zipper, {:if, m, [head, [do_block]]}), ctx}

      [head, [do_, else_]] ->
        if max_line(do_) > max_line(else_) do
          # we inverted the if/else blocks of this `if` statement in a previous pass (due to negators or unless)
          # shift comments etc to make it happy now
          if_ast(zipper, head, do_, else_, ctx)
        else
          {:cont, zipper, ctx}
        end

      _ ->
        {:cont, zipper, ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  # `with a <- b(), c <- d(), do: :ok, else: (_ -> :error)`
  # =>
  # `a = b(); c = d(); :ok`
  defp replace_with_statement(zipper, preroll) do
    [[{_do, do_body} | _elses] | preroll] = Enum.reverse(preroll)

    # RedundantWithClauseResult except we rewrote the `<-` to an `=`
    # with a, b, x <- y(), do: x
    # =>
    # a; b; y
    block =
      case preroll do
        [{:=, _, [lhs, rhs]} | rest] ->
          if nodes_equivalent?(lhs, do_body),
            do: [rhs | rest],
            else: [do_body | preroll]

        _ ->
          [do_body | preroll]
      end

    block = Enum.reverse(block)

    case Style.ensure_block_parent(zipper) do
      {:ok, zipper} ->
        zipper
        |> Zipper.prepend_siblings(block)
        |> Zipper.remove()

      :error ->
        # this is a very sad case, where the `with` is an arg to a function or the rhs of an assignment.
        # for now, just hacking a block with parens where the with use to be
        # x = with a, b, c, do: d
        # =>
        # x =
        #   (
        #     a
        #     b
        #     c
        #     d
        #   )
        # @TODO would be nice to changeto
        # a
        # b
        # c
        # x = d
        Zipper.update(zipper, fn {:with, meta, _} -> {:__block__, Keyword.take(meta, [:line]), block} end)
    end
  end

  defp left_arrow?({:<-, _, _}), do: true
  defp left_arrow?(_), do: false

  defp nodes_equivalent?(a, b) do
    # compare nodes without metadata
    Style.update_all_meta(a, fn _ -> nil end) == Style.update_all_meta(b, fn _ -> nil end)
  end

  defp if_ast(zipper, head, {_, _, _} = do_body, {_, _, _} = else_body, ctx) do
    do_ = {{:__block__, [line: nil], [:do]}, do_body}
    else_ = {{:__block__, [line: nil], [:else]}, else_body}
    if_ast(zipper, head, do_, else_, ctx)
  end

  defp if_ast(zipper, {_, meta, _} = head, {do_kw, do_body}, {else_kw, else_body}, ctx) do
    line = meta[:line]
    # ... why am i doing this again? hmm.
    do_body = Macro.update_meta(do_body, &Keyword.delete(&1, :end_of_expression))
    else_body = Macro.update_meta(else_body, &Keyword.delete(&1, :end_of_expression))

    max_do_line = max_line(do_body)
    max_else_line = max_line(else_body)
    end_line = max(max_do_line, max_else_line)

    # Change ast meta and comment lines to fit the `if` ast
    {do_, else_, comments} =
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

        do_ = {Style.set_line(do_kw, line), Style.shift_line(do_body, -else_size)}
        else_ = {Style.set_line(else_kw, max_else_line), Style.shift_line(else_body, do_size)}
        {do_, else_, Style.shift_comments(ctx.comments, shifts)}
      else
        # much simpler case -- just scootch things in the else down by 1 for the `else` keyword.
        do_ = {{:__block__, [line: line], [:do]}, do_body}
        else_ = Style.shift_line({{:__block__, [line: max_do_line], [:else]}, else_body}, 1)
        {do_, else_, Style.shift_comments(ctx.comments, max_do_line..max_else_line, 1)}
      end

    zipper
    |> Zipper.replace({:if, [do: [line: line], end: [line: end_line], line: line], [head, [do_, else_]]})
    |> run(%{ctx | comments: comments})
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
