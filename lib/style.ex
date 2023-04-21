# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style do
  @moduledoc """
  A Style takes AST and returns a transformed version of that AST.

  Because these transformations involve traversing trees (the "T" in "AST"), we wrap the AST in a structure
  called a Zipper to facilitate walking the trees.
  """

  alias Styler.Zipper

  @type context :: %{
          comment: [map()],
          file: :stdin | String.t()
        }

  @doc """
  `run` will be used with `Zipper.traverse_while/3`, meaning it will be executed on every node of the AST.

  You can skip traversing parts of the tree by returning a Zipper that's further along in the traversal, for example
  by calling `Zipper.skip(zipper)` to skip an entire subtree you know is of no interest to your Style.
  """
  @callback run(Zipper.zipper(), context()) :: {Zipper.command(), Zipper.zipper(), context()}

  @doc """
  Deletes `:line` from the node's meta

  If you expected `{:foo, foo_meta, [bar, baz, bop]` to give you a a single line like

    foo(bar, baz, bop)

  but instead got

    foo(
      bar,
      baz,
      bop
    )

  then it's likely that at least one of `bar`, `baz`, and/or `bop` have `:line` meta that's confusing the formatter
  and causing the multilining.

  This function fixes that problem.

    {:foo, foo_meta, Enum.map([bar, baz, bop], &Styler.Style.delete_line_meta/1)}
    # => foo(bar, baz, bop)
  """
  def delete_line_meta(ast_node), do: Macro.update_meta(ast_node, &Keyword.delete(&1, :line))

  @doc """
  Set the line of all comments with `line` in `range_start..range_end` to instead have line `range_start`
  """
  def displace_comments(comments, range) do
    Enum.map(comments, fn comment ->
      if comment.line in range do
        %{comment | line: range.first}
      else
        comment
      end
    end)
  end

  @doc """
  Change the `line` of all comments with `line` in `range` by adding `delta` to it.
  A positive delta will move the lines further down a file, while a negative delta will move them up.
  """
  def shift_comments(comments, range, delta) do
    Enum.map(comments, fn comment ->
      if comment.line in range do
        %{comment | line: comment.line + delta}
      else
        comment
      end
    end)
  end
end
