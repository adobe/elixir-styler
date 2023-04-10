# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.StyleCase do
  @moduledoc """
  Helpers around testing Style rules.
  """
  use ExUnit.CaseTemplate

  alias Styler.Zipper

  using options do
    style = options[:style]
    unless style, do: raise(ArgumentError, "missing required `:style` option")

    quote do
      @style unquote(style)
      import unquote(__MODULE__), only: [assert_style: 1, assert_style: 2]

      def style(code), do: unquote(__MODULE__).style(code, @style)
    end
  end

  defmacro assert_style(before, expected \\ nil) do
    expected = expected || before

    quote bind_quoted: [before: before, expected: expected] do
      expected = String.trim(expected)
      {styled_ast, styled} = style(before)

      if styled != expected and ExUnit.configuration()[:trace] do
        IO.puts("\n======Given=============\n")
        IO.puts(before)
        {before_ast, _} = Styler.string_to_quoted_with_comments(before)
        dbg(before_ast)
        IO.puts("======Expected==========\n")
        IO.puts(expected)
        {expected_ast, _} = Styler.string_to_quoted_with_comments(expected)
        dbg(expected_ast)
        IO.puts("======Got===============\n")
        IO.puts(styled)
        dbg(styled_ast)
        IO.puts("========================\n")
      end

      assert styled == expected
    end
  end

  def style(code, style) do
    {ast, comments} = Styler.string_to_quoted_with_comments(code)

    {zipper, %{comments: comments}} =
      ast
      |> Zipper.zip()
      |> Zipper.traverse_while(%{comments: comments, file: "test"}, &style.run/2)

    styled_ast = Zipper.root(zipper)
    styled_code = Styler.quoted_to_string(styled_ast, comments)
    {styled_ast, styled_code}
  end
end
