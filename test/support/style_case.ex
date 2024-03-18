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

  using do
    quote do
      import unquote(__MODULE__), only: [assert_style: 1, assert_style: 2, style: 1, style: 2]
    end
  end

  defmacro assert_style(before, expected, options) do
    quote bind_quoted: [before: before, expected: expected, options: options] do
      alias Styler.Zipper

      expected = String.trim(expected)
      {styled_ast, styled, styled_comments} = style(before, options)

      if styled != expected and ExUnit.configuration()[:trace] do
        IO.puts("\n======Given=============\n")
        IO.puts(before)
        {before_ast, before_comments} = Styler.string_to_quoted_with_comments(before)
        dbg(before_ast)
        dbg(before_comments)
        IO.puts("======Expected==========\n")
        IO.puts(expected)
        {expected_ast, expected_comments} = Styler.string_to_quoted_with_comments(expected)
        dbg(expected_ast)
        dbg(expected_comments)
        IO.puts("======Got===============\n")
        IO.puts(styled)
        dbg(styled_ast)
        dbg(styled_comments)
        IO.puts("========================\n")
      end

      # Ensure that every node has `line` meta so that we get better comments behaviour
      styled_ast
      |> Zipper.zip()
      |> Zipper.traverse(fn
        {{node, meta, _} = ast, _} = zipper ->
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

          unless meta[:line] || is_body_block? do
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

      assert expected == styled
      {_, restyled, _} = style(styled, options)

      assert restyled == styled, """
      expected styling to be idempotent, but a second pass resulted in more changes.

      first pass:
      ----
      #{styled}
      ----

      second pass:
      ----
      #{restyled}
      ----
      """
    end
  end

  def assert_style(no_change), do: assert_style(no_change, no_change, [])
  def assert_style(before, expected) when is_binary(expected), do: assert_style(before, expected, [])
  def assert_style(no_change, opts) when is_list(opts), do: assert_style(no_change, no_change, opts)

  def style(code, options \\ []) do
    {ast, comments} = Styler.string_to_quoted_with_comments(code)
    {styled_ast, comments} = Styler.style({ast, comments}, "testfile", [{:on_error, :raise} | options])

    try do
      styled_code = styled_ast |> Styler.quoted_to_string(comments) |> String.trim_trailing("\n")
      {styled_ast, styled_code, comments}
    rescue
      exception ->
        IO.inspect(styled_ast, label: [IO.ANSI.red(), "**Style created invalid ast:**", IO.ANSI.light_red()])
        reraise exception, __STACKTRACE__
    end
  end
end
