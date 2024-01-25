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
          comments: [map()],
          file: :stdin | String.t()
        }

  @doc """
  `run` will be used with `Zipper.traverse_while/3`, meaning it will be executed on every node of the AST.

  You can skip traversing parts of the tree by returning a Zipper that's further along in the traversal, for example
  by calling `Zipper.skip(zipper)` to skip an entire subtree you know is of no interest to your Style.
  """
  @callback run(Zipper.t(), context()) :: {Zipper.command(), Zipper.t(), context()}

  @doc "Recursively sets `:line` meta to `line`. Deletes `:newlines` unless `delete_lines: false` is passed"
  def set_line(ast_node, line, opts \\ []) do
    set_line = fn _ -> line end

    if Keyword.get(opts, :delete_newlines, true) do
      update_all_meta(ast_node, &(&1 |> update_line(set_line) |> Keyword.delete(:newlines)))
    else
      update_all_meta(ast_node, &update_line(&1, set_line))
    end
  end

  @doc "Recursively updates `:line` meta by adding `delta`"
  def shift_line(ast_node, delta) do
    shift_line = &(&1 + delta)
    update_all_meta(ast_node, &update_line(&1, shift_line))
  end

  defp update_line(meta, fun) do
    Enum.map(meta, fn
      {:line, line} -> {:line, fun.(line)}
      {k, v} when is_list(v) -> {k, update_line(v, fun)}
      kv -> kv
    end)
  end

  @doc "Traverses an ast node, updating all nodes' meta with `meta_fun`"
  def update_all_meta(node, meta_fun) do
    node
    |> Zipper.zip()
    |> Zipper.traverse(fn zipper -> Zipper.update(zipper, &Macro.update_meta(&1, meta_fun)) end)
    |> Zipper.root()
  end

  @doc """
  Returns the current node (wrapped in a `__block__` if necessary) if it's a valid place to insert additional nodes
  """
  @spec ensure_block_parent(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def ensure_block_parent(zipper) do
    valid_block_location? =
      case Zipper.up(zipper) do
        {{:__block__, _, _}, _} -> true
        {{:->, _, _}, _} -> true
        {{_, _}, _} -> true
        nil -> true
        _ -> false
      end

    if valid_block_location? do
      {:ok, find_nearest_block(zipper)}
    else
      :error
    end
  end

  @doc """
  Returns a zipper focused on the nearest node where additional nodes can be inserted (a "block").

  The nearest node is either the current node, an ancestor, or one of those two but wrapped in a new `:__block__` node.
  """
  @spec find_nearest_block(Zipper.t()) :: Zipper.t()
  def find_nearest_block(zipper) do
    case Zipper.up(zipper) do
      # parent is a block!
      {{:__block__, _, _}, _} -> zipper
      # when a statement is an only child, it doesn't get a block wrapper
      # only child of a right arrow
      {{:->, _, _}, _} -> wrap_in_block(zipper)
      # only child of a `do` block
      {{_, _}, _} -> wrap_in_block(zipper)
      # one line snippet
      nil -> wrap_in_block(zipper)
      # we're in a pipe, assignment, function call, etc. gotta keep going up looking for a block
      parent -> find_nearest_block(parent)
    end
  end

  # give it a block parent, then step back to the child - we can insert next to it now that it's in a block
  defp wrap_in_block(zipper) do
    zipper
    |> Zipper.update(fn {_, meta, _} = node -> {:__block__, Keyword.take(meta, [:line]), [node]} end)
    |> Zipper.down()
  end

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
    shift_comments(comments, [{range, delta}])
  end

  @doc """
  Perform a series of shifts in a single pass.

  When shifting comments from block A to block B, naively using two passes of `shift_comments/3` would result
  in all comments ending up in either region A or region B (because A would move to B, then all B back to A)
  This function exists to make sure that a comment is only moved once during the swap.
  """
  def shift_comments(comments, shifts) do
    comments
    |> Enum.map(fn comment ->
      if delta = Enum.find_value(shifts, fn {range, delta} -> comment.line in range && delta end) do
        %{comment | line: comment.line + delta}
      else
        comment
      end
    end)
    |> Enum.sort_by(& &1.line)
  end
end
