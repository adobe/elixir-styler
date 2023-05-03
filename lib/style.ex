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

    {:foo, foo_meta, Enum.map([bar, baz, bop], &Styler.Style.drop_line_meta/1)}
    # => foo(bar, baz, bop)
  """
  def drop_line_meta(ast_node) do
    update_all_meta(ast_node, &Keyword.drop(&1, [:line, :closing, :last, :newlines]))
  end

  @doc "Traverses an ast node, updating all nodes' meta with `meta_fun`"
  def update_all_meta(node, meta_fun) do
    node
    |> Zipper.zip()
    |> Zipper.traverse(fn zipper -> Zipper.update(zipper, &Macro.update_meta(&1, meta_fun)) end)
    |> Zipper.root()
  end

  @doc """
  Ensure the parent node can have multiple children.

  If a context-changing node (a `do end` block or an `->` arrow block) is encountered
  the child is wrapped in a `:__block__`

  Other nodes (pipes, assignments) can only have a fixed number of children. This function
  will recursively traverse up the zipper until it's found the parents of those nodes.
  """
  def ensure_block_parent(zipper) do
    case Zipper.up(zipper) do
      # Pipes and assignments have exactly two children - keep going up
      {{:|>, _, _}, _} = parent -> ensure_block_parent(parent)
      {{:=, _, _}, _} = parent -> ensure_block_parent(parent)
      # the current zipper is an only-child of an arrow ala `true -> :ok`
      # we need to change the body of the arrow to be a `:__block__` so our `:ok` can have siblings
      {{:->, _, _}, _} -> wrap_in_block(zipper)
      # parent is an only-child of a `do` block
      {{_, _}, _} -> wrap_in_block(zipper)
      # a snippet or script where the zipper is a single child with no parent above it
      nil -> wrap_in_block(zipper)
      # since its parent isn't one of the problem AST above, the current zipper's parent can have multiple children, so we're done
      # could be `:def`, `:__block__`, ...
      _ -> zipper
    end
  end

  # give it a block parent, then step back to the child - we can insert next to it now that it's in a block
  defp wrap_in_block(zipper), do: zipper |> Zipper.update(&{:__block__, [], [&1]}) |> Zipper.down()

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
