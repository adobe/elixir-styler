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

  @type command :: :cont | :skip | :halt
  @type comments :: [map()]

  @doc """
  `run` will be used with `Zipper.traverse_while/3`, meaning it will be executed on every node of the AST.

  You can skip traversing parts of the tree by returning a Zipper that's further along in the traversal, for example
  by calling `Zipper.skip(zipper)` to skip an entire subtree you know is of no interest to your Style.
  """
  @callback run(Zipper.zipper(), comments()) :: Zipper.zipper() | {command(), Zipper.zipper(), comments()}

  @doc false
  # this lets Styles optionally implement as though they're running inside of `Zipper.traverse`
  # or `Zipper.traverse_while` for finer-grained control
  def wrap_run(style) do
    fn zipper, comments ->
      case style.run(zipper, comments) do
        {next, {_, _} = _zipper, _comments} = command when next in ~w(cont halt skip)a -> command
        zipper -> {:cont, zipper, comments}
      end
    end
  end

  @doc """
  This is a convenience function for adjusting the metadata on the specified
  AST node and its descendents such that they are moved to the same line as the
  top AST node, displacing the comments associated with those lines above the
  collapsed line.

  `comments` should be the same data structure passed as the second argument to
  the style's `run/2` function, which is the same data structure returned by
  Elixir's `Code.string_to_quoted_with_comments!/2`.

  For example, if the following code were to be styled such that it became a one-liner:

      def(
        # This is arg 1
        arg1,
        # This is arg 2
        arg2
      ), do: :ok

  then this function would manipulate the `comments` such that they would end
  up being formatted like this:

      # This is arg1
      # This is arg2
      def(arg1, arg2), do: :ok
  """
  def collapse_lines({_node, meta, _children} = ast_node, comments) do
    set_to_first = fn _ -> meta[:line] end

    {range, ast_node} =
      update_all_meta(ast_node, fn meta ->
        meta
        |> Keyword.replace_lazy(:line, set_to_first)
        |> Keyword.replace_lazy(:closing, &Keyword.replace_lazy(&1, :line, set_to_first))
        |> Keyword.delete(:newlines)
      end)

    comments =
      Enum.map(comments, fn comment ->
        if comment.line in range do
          Map.update!(comment, :line, set_to_first)
        else
          comment
        end
      end)

    {ast_node, comments}
  end

  def collapse_lines(ast_node, comments), do: {ast_node, comments}

  @doc """
  This is a convenience function for adjusting the metadata on the specified
  AST node and its descendents such that they are moved `delta` lines, along
  with the comments associated with those lines.(negative `delta` means to
  shift the comments up, and positive means to shift them down).
  """
  def shift_lines(ast_node, delta, comments) do
    apply_delta = fn line -> line + delta end

    {range, ast_node} =
      update_all_meta(ast_node, fn meta ->
        meta
        |> Keyword.replace_lazy(:line, apply_delta)
        |> Keyword.replace_lazy(:closing, &Keyword.replace_lazy(&1, :line, apply_delta))
      end)

    comments =
      Enum.map(comments, fn comment ->
        if comment.line in range do
          Map.update!(comment, :line, apply_delta)
        else
          comment
        end
      end)

    {ast_node, comments}
  end

  #defp update_all_meta(children, meta_fun) when is_list(children) do
  #  {line_ranges, children} =
  #    children
  #    |> Enum.map(&update_all_meta(&1, meta_fun))
  #    |> Enum.unzip()

  #  range = Enum.reduce(line_ranges, nil, fn acc, range ->
  #    if acc do
  #      min(acc.first, range.first)..max(acc.last, range.last)
  #    else
  #      range
  #    end
  #  end)

  #  {range, children}
  #end

  #defp update_all_meta({node, meta, nil = children}, meta_fun) do
  #  first = meta[:line]
  #  last = meta[:closing][:line] || meta[:line]
  #  {first..last, {node, meta_fun.(meta), children}}
  #end

  #defp update_all_meta({node, meta, children}, meta_fun) do
  #  first = meta[:line]
  #  last = meta[:closing][:line] || meta[:line]

  #  {line_ranges, children} =
  #    children
  #    |> Enum.map(&update_all_meta(&1, meta_fun))
  #    |> Enum.unzip()

  #  range = Enum.reduce(line_ranges, first..last, fn acc, range ->
  #    min(acc.first, range.first)..max(acc.last, range.last)
  #  end)

  #  {range, {node, meta_fun.(meta), children}}
  #end

  defp update_all_meta(node, meta_fun) do
    {zipper, range} =
    node
    |> Zipper.zip()
    |> Zipper.traverse(nil, fn
      {{node, meta, children}, _} = zipper, acc ->
        first = meta[:line]
        last = meta[:closing][:line] || meta[:line]
        range = if acc do
          min(acc.first, first)..max(acc.last, last)
        else
          first..last
        end

        {Zipper.replace(zipper, {node, meta_fun.(meta), children}), range}

      zipper, acc ->
        {zipper, acc}
    end)

    {range, Zipper.root(zipper)}
  end
end
