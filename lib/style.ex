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
  This is a convenience function for when a style needs to compact or eliminate
  a range of lines, but preserve any comments in those lines by displacing them
  all to be start of the compacted lines.

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

  Obviously, it would then be up to the developer to rewrite the comments to
  that they're more descriptive about what they are referring to.
  """
  def displace_comments(comments, range_of_lines) do
    Enum.map(comments, fn comment ->
      if comment.line in range_of_lines do
        %{comment | line: range_of_lines.first}
      else
        comment
      end
    end)
  end

  @doc """
  This is a convenience function for shifting all comments after `after_line`
  by `delta` lines (negative `delta` means to shift the comments up, and
  positive means to shift them down).

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
  def shift_comments(comments, after_line, delta) do
    Enum.map(comments, fn comment ->
      if comment.line > after_line do
        %{comment | line: max(0, comment.line + delta)}
      else
        comment
      end
    end)
  end
end
