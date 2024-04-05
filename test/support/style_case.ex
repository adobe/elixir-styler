# Copyright 2024 Adobe. All rights reserved.
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

  using options do
    quote do
      import unquote(__MODULE__),
        only: [assert_style: 1, assert_style: 2, style: 1, style: 2, format_diff: 2, format_diff: 3]

      @filename unquote(options)[:filename] || "testfile"
    end
  end

  defmacro assert_style(before, expected \\ nil) do
    expected = expected || before

    quote bind_quoted: [before: before, expected: expected], location: :keep do
      alias Styler.Zipper

      expected = String.trim(expected)
      {styled_ast, styled, styled_comments} = style(before, @filename)

      if styled != expected and ExUnit.configuration()[:trace] do
        IO.puts("\n======Given=============\n")
        IO.puts(before)
        {before_ast, before_comments} = Styler.string_to_quoted_with_comments(before)
        dbg(before_ast)
        dbg(before_comments)
        IO.puts("======Expected AST==========\n")
        {expected_ast, expected_comments} = Styler.string_to_quoted_with_comments(expected)
        dbg(expected_ast)
        dbg(expected_comments)
        IO.puts("======Got AST===============\n")
        dbg(styled_ast)
        dbg(styled_comments)
        IO.puts("========================\n")
      end

      if expected == styled do
        assert true
      else
        flunk(format_diff(expected, styled))
      end

      # Make sure we're keeping lines in check
      styled_ast
      |> Zipper.zip()
      |> Zipper.traverse(-1, fn
        {{node, meta, _} = ast, _} = zipper, previous_line ->
          line = meta[:line]

          up = Zipper.up(zipper)
          # body blocks - for example, the block node for an anonymous function - don't have line meta
          # yes, i just did `&& case`. sometimes it's funny to write ugly things in my project that's all about style.
          # i believe they calls that one "irony"
          is_body_block? =
            node == :__block__ &&
              case up && Zipper.node(up) do
                # top of a snippet
                nil -> true
                # do/else/etc
                {{:__block__, _, [_]}, {:__block__, [], _}} -> true
                # anon fun
                {:->, _, _} -> true
                _ -> false
              end

          # @TODO lots of the `pipes` rules violate this. no surprise since that was some of the earliest code!
          # if line do
          #   assert previous_line <= line
          # end

          unless line || is_body_block? do
            IO.puts("missing `:line` meta in node:")
            dbg(ast)

            IO.puts("tree:")
            dbg(styled_ast)

            IO.puts("expected:")
            dbg(elem(Styler.string_to_quoted_with_comments(expected), 0))

            IO.puts("code:\n#{styled}")
            flunk("")
          end

          {zipper, line || previous_line}

        zipper, previous ->
          {zipper, previous}
      end)

      # Idempotency
      {_, restyled, _} = style(styled, @filename)

      if restyled == styled do
        assert true
      else
        flunk(
          format_diff(restyled, styled, "expected styling to be idempotent, but a second pass resulted in more changes.")
        )
      end
    end
  end

  def style(code, filename \\ "testfile") do
    {ast, comments} = Styler.string_to_quoted_with_comments(code)
    {styled_ast, comments} = Styler.style({ast, comments}, filename, on_error: :raise)

    try do
      styled_code = styled_ast |> Styler.quoted_to_string(comments) |> String.trim_trailing("\n")
      {styled_ast, styled_code, comments}
    rescue
      exception ->
        IO.inspect(styled_ast, label: [IO.ANSI.red(), "**Style created invalid ast:**", IO.ANSI.light_red()])
        reraise exception, __STACKTRACE__
    end
  end

  def format_diff(expected, styled, prelude \\ "Styling produced unexpected results") do
    # reaching into private ExUnit stuff, uh oh!
    # this gets us the nice diffing from ExUnit while allowing us to print our code blocks as strings rather than inspected strings
    {%{left: expected, right: styled}, _} = ExUnit.Diff.compute(expected, styled, :==)
    expected = for {diff?, content} <- expected.contents, do: if(diff?, do: [:red, content, :reset], else: content)
    styled = for {diff?, content} <- styled.contents, do: if(diff?, do: [:green, content, :reset], else: content)
    header = IO.ANSI.format([:red, prelude, :reset])

    expected =
      [[:cyan, "expected:\n", :reset] | expected]
      |> IO.ANSI.format()
      |> to_string()
      |> Macro.unescape_string()
      |> String.replace("\n", "\n  ")

    styled =
      [[:cyan, "styled:\n", :reset] | styled]
      |> IO.ANSI.format()
      |> to_string()
      |> Macro.unescape_string()
      |> String.replace("\n", "\n  ")

    """
    #{header}
    #{expected}
    #{styled}
    """
  end
end
