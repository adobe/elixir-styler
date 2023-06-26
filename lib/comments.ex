# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Comments do
  @moduledoc """
  A Style takes AST and returns a transformed version of that AST.

  Because these transformations involve traversing trees (the "T" in "AST"), we wrap the AST in a structure
  called a Zipper to facilitate walking the trees.
  """

  def preceding(comments, line) do
    preceding_line = line - 1

    relevant_comments =
      comments
      |> Enum.reverse()
      |> Enum.drop_while(&(&1.line not in [line, preceding_line]))

    if Enum.empty?(relevant_comments) do
      []
    else
      [first = %{line: line} | relevant_comments] = relevant_comments

      relevant_comments
      |> Enum.reduce_while({line, [first]}, fn comment, {line, preceding} ->
        if comment.line == line - 1 do
          {:cont, {comment.line, [comment | preceding]}}
        else
          {:halt, {:ignored, preceding}}
        end
      end)
      |> elem(1)
    end
  end

  @doc """
  Set the line of all comments with `line` in `range_start..range_end` to instead have line `range_start`
  """
  def displace(comments, range) do
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
  def shift(comments, range, delta) do
    Enum.map(comments, fn comment ->
      if comment.line in range do
        %{comment | line: comment.line + delta}
      else
        comment
      end
    end)
  end
end
