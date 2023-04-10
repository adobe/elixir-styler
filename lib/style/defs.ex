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
  NOT ENABLED
  Currently has a bug where it puts comments into bad places no matter what, since it's
  always rewriting every head. It's been run on our codebase once though...

  --------------------------------------

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
  """

  @behaviour Styler.Style

  alias Styler.Zipper
  alias Styler.Style

  # a def with no body like
  #
  #  def example(foo, bar \\ nil)
  #
  def run({{def, meta, [head]}, _} = zipper, ctx) when def in [:def, :defp] do
    {_fn_name, head_meta, _children} = head
    first_line = meta[:line]
    last_line = head_meta[:closing][:line]

    comments =
      if first_line == last_line do
        ctx.comments
      else
        Style.displace_comments(ctx.comments, first_line..last_line)
      end

    # There won't be any defs deeper in here, so lets skip ahead if we can
    head = flatten_head(head, meta[:line])
    {:skip, Zipper.replace(zipper, {def, meta, [head]}), %{ctx | comments: comments}}
  end

  # all the other kinds of defs!
  def run({{def, def_meta, [head, body]}, _} = zipper, ctx) when def in [:def, :defp] do
    if def_meta[:do] do
      # we're in a `def do ... end`
      def_start = def_meta[:line]
      def_do = def_meta[:do][:line]
      def_end = def_meta[:end][:line]

      delta = def_start - def_do
      apply_delta = &(&1 + delta)

      # collapse everything in the head from `def` to `do` onto one line
      def_meta =
        def_meta
        |> Keyword.replace_lazy(:do, &Keyword.put(&1, :line, def_start))
        |> Keyword.replace_lazy(:end, &Keyword.update!(&1, :line, apply_delta))

      head = flatten_head(head, def_start)

      # move all body lines up by the amount we squished the head by
      body = update_all_meta(body, shift_lines(apply_delta))

      # move comments in the head to the top, and move comments in the body up by the delta
      comments =
        ctx.comments
        |> Style.displace_comments(def_start..def_do)
        |> Style.shift_comments(def_do..def_end, delta)

      # @TODO this skips checking the body, which can be incorrect if therey's a `quote do def do ...` inside of it
      node = {def, def_meta, [head, body]}
      {:skip, Zipper.replace(zipper, node), %{ctx | comments: comments}}
    else
      # we're in a `def, do:`
      [{
        {:__block__, do_meta, [:do]},
        {_, body_meta, _}
      }] = body
      def_start = def_meta[:line]
      def_do = do_meta[:line]
      def_end = body_meta[:closing][:line] || def_do

      head = flatten_head(head, def_start)

      # collapse the whole thing to one line
      to_same_line = fn _ -> def_start end
      body = update_all_meta(body, collapse_lines(to_same_line))

      # move all comments to the top
      comments =
        ctx.comments
        |> Style.displace_comments(def_start..def_end)

      # @TODO this skips checking the body, which can be incorrect if therey's a `quote do def do ...` inside of it
      node = {def, def_meta, [head, body]}
      {:skip, Zipper.replace(zipper, node), %{ctx | comments: comments}}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp collapse_lines(line_mover) do
    fn meta ->
      meta
      |> Keyword.replace_lazy(:line, line_mover)
      |> Keyword.replace_lazy(:closing, &Keyword.replace_lazy(&1, :line, line_mover))
      |> Keyword.delete(:newlines)
    end
  end

  defp shift_lines(line_mover) do
    fn meta ->
      meta
      |> Keyword.replace_lazy(:line, line_mover)
      |> Keyword.replace_lazy(:closing, &Keyword.replace_lazy(&1, :line, line_mover))
    end
  end

  defp flatten_head(head, line) do
    update_all_meta(head, fn meta ->
      meta
      |> Keyword.replace(:line, line)
      |> Keyword.replace(:closing, line: line)
      |> Keyword.replace(:last, line: line)
      |> Keyword.delete(:newlines)
    end)
  end

  defp update_all_meta(node, meta_fun) do
    node
    |> Zipper.zip()
    |> Zipper.traverse(fn
      {{node, meta, children}, _} = zipper -> Zipper.replace(zipper, {node, meta_fun.(meta), children})
      zipper -> zipper
    end)
    |> Zipper.root()
  end
end
