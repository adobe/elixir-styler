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

  # a def with no body like
  #
  #  def example(foo, bar \\ nil)
  #
  def run({{def, meta, [head]}, _} = zipper, ctx) when def in [:def, :defp] do
    # There won't be any defs deeper in here, so lets skip ahead if we can
    {:skip, Zipper.replace(zipper, {def, meta, [flatten_head(head, meta[:line])]}), ctx}
  end

  # all the other kinds of defs!
  def run({{def, def_meta, [head, body]}, _} = zipper, ctx) when def in [:def, :defp] do
    def_start_line = def_meta[:line]
    # order matters here! the end of the def is where the `do`s line is - but only if there's a do end block.
    # otherwise it's just where the end of the (def) expression is.
    def_end_line = (def_meta[:do] || def_meta[:end_of_expression])[:line]

    if def_start_line == def_end_line do
      {:skip, zipper, ctx}
    else
      head = flatten_head(head, def_start_line)

      {def_meta, body_meta_rewriter} =
        if def_meta[:do] do
          # we're in a `def do ... end`
          delta = def_end_line - def_start_line
          up_by_delta = &(&1 - delta)

          # this is what does the shrinking of the `def ... do` stanza
          def_meta =
            def_meta
            |> Keyword.replace_lazy(:do, &Keyword.put(&1, :line, def_start_line))
            |> Keyword.replace_lazy(:end, &Keyword.update!(&1, :line, up_by_delta))

          # move all body line #s up by the amount we squished the head by
          {def_meta, collapse_lines(up_by_delta)}
        else
          # we're in a `def, do:`
          to_same_line = fn _ -> def_start_line end
          {def_meta, collapse_lines(to_same_line)}
        end

      body = update_all_meta(body, body_meta_rewriter)

      # There won't be any defs deeper in here, so lets skip ahead if we can
      # @TODO this skips checking the body, which can be incorrect if therey's a `quote do def do ...` inside of it
      {:skip, Zipper.replace(zipper, {def, def_meta, [head, body]}), ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp collapse_lines(line_mover) do
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
