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
      @ordered_siblings unquote(options)[:ordered_siblings] || false
    end
  end

  setup_all do
    Styler.Config.set([])
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
      |> Zipper.traverse(fn
        {{node, meta, _} = ast, _} = zipper ->
          line = meta[:line]

          up = Zipper.up(zipper)
          # body blocks - for example, the block node for an anonymous function - don't have line meta
          # yes, i just did `&& case`. sometimes it's funny to write ugly things in my project that's all about style.
          # i believe they calls that one "irony"
          body_block? =
            node == :__block__ &&
              case up && Zipper.node(up) do
                # top of a snippet
                nil -> true
                # do/else/etc
                {{:__block__, _, [_]}, {:__block__, [], _}} -> true
                # anonymous function
                {:->, _, _} -> true
                _ -> false
              end

          if @ordered_siblings do
            case Zipper.left(zipper) do
              {{_, prev_meta, _} = prev, _} ->
                if prev_meta[:line] && meta[:line] && prev_meta[:line] > meta[:line] do
                  if ExUnit.configuration()[:trace] do
                    dbg(prev)
                    dbg(ast)
                  end

                  assert(prev_meta[:line] <= meta[:line], "Previous node had a higher line than this node")
                end

              _ ->
                :ok
            end
          end

          if is_nil(line) and not body_block? do
            IO.puts("missing `:line` meta in node:")
            dbg(ast)

            IO.puts("tree:")
            dbg(styled_ast)

            IO.puts("expected:")
            dbg(elem(Styler.string_to_quoted_with_comments(expected), 0))

            IO.puts("code:\n#{styled}")
            flunk("")
          end

          zipper

        zipper ->
          zipper
      end)

      # Idempotency
      {_, restyled, _} = style(styled, @filename)

      if restyled == styled do
        assert true
      else
        flunk(
          format_diff(styled, restyled, "expected styling to be idempotent, but a second pass resulted in more changes.")
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

    expected =
      for {diff?, content} <- expected.contents do
        cond do
          diff? and String.trim_leading(Macro.unescape_string(content)) == "" -> [:red_background, content, :reset]
          diff? -> [:red, content, :reset]
          true -> content
        end
      end

    styled =
      for {diff?, content} <- styled.contents do
        cond do
          diff? and String.trim_leading(Macro.unescape_string(content)) == "" -> [:green_background, content, :reset]
          diff? -> [:green, content, :reset]
          true -> content
        end
      end

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
