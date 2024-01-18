# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.DeprecationsTest do
  use Styler.StyleCase, async: true

  test "Logger.warn to Logger.warning" do
    assert_style("Logger.warn(foo)", "Logger.warning(foo)")
    assert_style("Logger.warn(foo, bar)", "Logger.warning(foo, bar)")
  end

  test "Path.safe_relative_to/2 to Path.safe_relative/2" do
    assert_style("Path.safe_relative_to(foo, bar)", "Path.safe_relative(foo, bar)")

    assert_style(
      """
      "FOO"
      |> String.downcase()
      |> Path.safe_relative_to("/")
      """,
      """
      "FOO"
      |> String.downcase()
      |> Path.safe_relative("/")
      """
    )
  end

  describe "1.16 deprecations" do
    @describetag skip: Version.match?(System.version(), "< 1.16.0-dev")

    test "File.stream!(path, modes, line_or_bytes) to File.stream!(path, line_or_bytes, modes)" do
      assert_style(
        "File.stream!(path, [encoding: :utf8, trim_bom: true], :line)",
        "File.stream!(path, :line, encoding: :utf8, trim_bom: true)"
      )

      assert_style(
        "f |> File.stream!([encoding: :utf8, trim_bom: true], :line) |> Enum.take(2)",
        "f |> File.stream!(:line, encoding: :utf8, trim_bom: true) |> Enum.take(2)"
      )
    end

    test "negative steps with [Enum|String].slice/2" do
      for mod <- ~w(Enum String) do
        assert_style("#{mod}.slice(x, 1..-2)", "#{mod}.slice(x, 1..-2//1)")
        assert_style("#{mod}.slice(x, -1..-2)", "#{mod}.slice(x, -1..-2//1)")
        assert_style("#{mod}.slice(x, 2..1)", "#{mod}.slice(x, 2..1//1)")
        assert_style("#{mod}.slice(x, 1..3)")
        assert_style("#{mod}.slice(x, ..)")

        # piped
        assert_style("foo |> bar() |> #{mod}.slice(1..-2)", "foo |> bar() |> #{mod}.slice(1..-2//1)")
        assert_style("foo |> bar() |> #{mod}.slice(-1..-2)", "foo |> bar() |> #{mod}.slice(-1..-2//1)")
        assert_style("foo |> bar() |> #{mod}.slice(2..1)", "foo |> bar() |> #{mod}.slice(2..1//1)")
        assert_style("foo |> bar() |> #{mod}.slice(1..3)")

        # non-trivial ranges
        assert_style "#{mod}.slice(x, y..z)"
        assert_style "#{mod}.slice(x, (y - 1)..f)"
        assert_style("foo |> bar() |> #{mod}.slice(x..y)")
      end
    end
  end
end
