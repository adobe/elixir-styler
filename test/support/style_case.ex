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
      import unquote(__MODULE__), only: [assert_style: 1, assert_style: 2, style: 1]
    end
  end

  defmacro assert_style(before, expected \\ nil) do
    expected = expected || before

    quote bind_quoted: [before: before, expected: expected] do
      expected = String.trim(expected)
      {styled_ast, styled, styled_comments} = style(before)

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

      assert expected == styled
      {_, restyled, _} = style(styled)

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

  def style(code) do
    {ast, comments} = Styler.string_to_quoted_with_comments(code)
    {styled_ast, comments} = Styler.style({ast, comments}, "testfile", on_error: :raise)

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
