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
  def run({{def, meta, [head]}, _} = zipper, comments) when def in [:def, :defp] do
    {_fn_name, head_meta, _children} = head
    first_line = meta[:line]
    last_line = head_meta[:closing][:line]

    {head, comments} = Style.collapse_lines(head, comments)

    # There won't be any defs deeper in here, so lets skip ahead if we can
    {:skip, Zipper.replace(zipper, {def, meta, [head]}), comments}
  end

  # all the other kinds of defs!
  def run({{def, def_meta, [head, body]} = node, _} = zipper, comments) when def in [:def, :defp] do
    if def_meta[:do] do
      # we're in a `def do ... end`
      def_start = def_meta[:line]
      def_do = def_meta[:do][:line]
      def_end = def_meta[:end][:line]

      delta = def_start - def_do
      apply_delta = &(&1 + delta)

      # collapse everything in the head from `def` to `do` onto one line
      {head, comments} = Style.collapse_lines(head, comments)

      def_meta =
        def_meta
        |> Keyword.replace_lazy(:do, &Keyword.put(&1, :line, def_start))
        |> Keyword.replace_lazy(:end, &Keyword.update!(&1, :line, apply_delta))

      # move all body lines up by the amount we squished the head by
      {body, comments} = Style.shift_lines(body, delta, comments)

      {:skip, Zipper.replace(zipper, {def, def_meta, [head, body]}), comments}
    else
      # we're in a `def, do:`
      [{
        {:__block__, do_meta, [:do]},
        {_, body_meta, _}
      }] = body
      def_start = def_meta[:line]
      def_do = do_meta[:line]
      def_end = body_meta[:closing][:line] || def_do

      # collapse the whole def to one line if we can
      {node, comments} = Style.collapse_lines(node, comments)

      {:skip, Zipper.replace(zipper, node), comments}
    end
  end

  def run(zipper, _comments), do: zipper
end
