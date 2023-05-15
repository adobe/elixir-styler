# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Defs do
  @moduledoc """
  Styles function heads so that they're as small as possible.

  The goal is that a function head fits on a single line.

  This isn't a Credo issue, and the formatter is fine with either approach. But Styler has opinions!

  Ex:

  This long declaration

      def foo(%{
        bar: baz
      }) do
        ...
      end

  Becomes

      def foo(%{bar: baz}) do
        ...
      end

  * Credo.Check.Readability.PreferImplicitTry
  * Credo.Check.Readability.ParenthesesOnZeroArityDefs
  * Credo.Check.Consistency.ParameterPatternMatching
  """

  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  def run({{def, _, _}, _} = zipper, ctx) when def in [:def, :defp] do
    {zipper, ctx} =
      zipper
      |> Zipper.update(&style/1)
      |> flatten(ctx)

    {:cont, zipper, ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  # Remove parens from 0 arity funs (Credo.Check.Readability.ParenthesesOnZeroArityDefs)
  defp style({def, dm, [{fun, funm, []} | rest]}), do: style({def, dm, [{fun, funm, nil} | rest]})
  # `Credo.Check.Readability.PreferImplicitTry`
  defp style({def, dm, [head, [{_, {:try, _, [try_children]}}]]}), do: style({def, dm, [head, try_children]})
  # Credo.Check.Consistency.ParameterPatternMatching
  defp style({def, dm, [{f, fm, params} | rest]}), do: {def, dm, [{f, fm, Style.put_matches_on_right(params)} | rest]}

  # a def with no body like
  #
  #  def example(foo, bar \\ nil)
  #
  defp flatten({{def, meta, [head]}, _} = zipper, ctx) do
    {_fn_name, head_meta, _children} = head
    first_line = meta[:line]
    last_line = head_meta[:closing][:line]

    if first_line == last_line do
      # Already collapsed
      {zipper, ctx}
    else
      comments = Style.displace_comments(ctx.comments, first_line..last_line)
      node = {def, meta, [Style.set_line_meta_to_line(head, meta[:line])]}
      {Zipper.replace(zipper, node), %{ctx | comments: comments}}
    end
  end

  # all the other kinds of defs!
  defp flatten({{def, def_meta, [head, body]}, _} = zipper, ctx) do
    {def_line, do_line, end_line} =
      if def_meta[:do] do
        # This is a def with a do block, like
        #
        #  def example(foo, bar \\ nil) do
        #    :ok
        #  end
        #
        def_line = def_meta[:line]
        do_line = def_meta[:do][:line]
        end_line = def_meta[:end][:line]
        {def_line, do_line, end_line}
      else
        # This is a def with a keyword do, like
        #
        #  def example(foo, bar \\ nil), do: :ok
        #
        [{{:__block__, do_meta, [:do]}, {_, body_meta, _}}] = body
        def_line = def_meta[:line]
        do_line = do_meta[:line]
        end_line = body_meta[:closing][:line] || do_meta[:line]
        {def_line, do_line, end_line}
      end

    delta = def_line - do_line
    move_up = &(&1 + delta)
    set_to_def_line = fn _ -> def_line end

    cond do
      def_line == end_line ->
        # Already collapsed
        {zipper, ctx}

      def_meta[:do] ->
        # We're working on a def do ... end
        def_meta =
          def_meta
          |> Keyword.replace_lazy(:do, &Keyword.update!(&1, :line, set_to_def_line))
          |> Keyword.replace_lazy(:end, &Keyword.update!(&1, :line, move_up))

        head = Style.set_line_meta_to_line(head, def_line)
        body = Style.update_all_meta(body, shift_lines(move_up))
        node = {def, def_meta, [head, body]}

        comments =
          ctx.comments
          |> Style.displace_comments(def_line..do_line)
          |> Style.shift_comments(do_line..end_line, delta)

        {Zipper.replace(zipper, node), %{ctx | comments: comments}}

      true ->
        # We're working on a Keyword def do:
        node = Style.set_line_meta_to_line({def, def_meta, [head, body]}, def_line)
        comments = Style.displace_comments(ctx.comments, def_line..end_line)

        {Zipper.replace(zipper, node), %{ctx | comments: comments}}
    end
  end

  defp shift_lines(line_mover) do
    fn meta ->
      meta
      |> Keyword.replace_lazy(:line, line_mover)
      |> Keyword.replace_lazy(:closing, &Keyword.replace_lazy(&1, :line, line_mover))
    end
  end
end
