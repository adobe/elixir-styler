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
  This is a convenience function for shifting all comments in a `range` by
  `delta` lines (negative `delta` means to shift the comments up, and positive
  means to shift them down).

  For example, if the following code were to be styled such each `def` became a one-liner:

      # Positive numbers are good
      def(
        arg1,
        arg2
      ) when is_integer(arg1) and arg1 >= 0, do: :ok

      # Negative numbers are are bad
      def(
        arg1,
        arg2
      ), do: :error

      # This comment comes at the end

  then this function would manipulate the `comments` such that they would end
  up being formatted like this:

      # Positive numbers are good
      def(arg1, arg2) when is_integer(arg1) and arg1 >= 0, do: :ok

      # Negative numbers are are bad
      def(arg1, arg2), do: :error

      # This comment comes at the end
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
