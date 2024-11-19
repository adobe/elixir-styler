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

  test "matching ranges" do
    assert_style "first..last = range", "first..last//_ = range"
    assert_style "^first..^last = range", "^first..^last//_ = range"
    assert_style "first..last = x = y", "first..last//_ = x = y"
    assert_style "y = first..last = x", "y = first..last//_ = x"

    assert_style "def foo(x..y), do: :ok", "def foo(x..y//_), do: :ok"
    assert_style "def foo(a, x..y = z), do: :ok", "def foo(a, x..y//_ = z), do: :ok"
    assert_style "def foo(%{a: x..y = z}), do: :ok", "def foo(%{a: x..y//_ = z}), do: :ok"

    assert_style "with a..b = c <- :ok, d..e <- :better, do: :ok", "with a..b//_ = c <- :ok, d..e//_ <- :better, do: :ok"

    assert_style(
      """
      case x do
        a..b = c -> :ok
        d..e -> :better
      end
      """,
      """
      case x do
        a..b//_ = c -> :ok
        d..e//_ -> :better
      end
      """
    )
  end

  test "List.zip/1" do
    assert_style "List.zip(foo)", "Enum.zip(foo)"
    assert_style "foo |> List.zip |> bar", "foo |> Enum.zip() |> bar()"
    assert_style "foo |> List.zip", "Enum.zip(foo)"
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
  end

  test "~R is deprecated in favor of ~r" do
    assert_style(~s|Regex.match?(~R/foo/, "foo")|, ~s|Regex.match?(~r/foo/, "foo")|)
  end

  test "replace Date.range/2 with Date.range/3 when first > last" do
    assert_style("Date.range(~D[2000-01-01], ~D[1999-01-01])", "Date.range(~D[2000-01-01], ~D[1999-01-01], -1)")

    assert_style(
      "~D[2000-01-01] |> Date.range(~D[1999-01-01]) |> foo()",
      "~D[2000-01-01] |> Date.range(~D[1999-01-01], -1) |> foo()"
    )

    assert_style("Date.range(~D[1999-01-01], ~D[2000-01-01])")
    assert_style("Date.range(~D[1999-01-01], ~D[1999-01-01])")
  end

  test "use :eof instead of :all in IO.read/2 and IO.binread/2" do
    assert_style("IO.read(:all)", "IO.read(:eof)")
    assert_style("IO.read(device, :all)", "IO.read(device, :eof)")
    assert_style("IO.binread(:all)", "IO.binread(:eof)")
    assert_style("IO.binread(device, :all)", "IO.binread(device, :eof)")

    assert_style(
      "file |> IO.binread(:all) |> :binary.bin_to_list()",
      "file |> IO.binread(:eof) |> :binary.bin_to_list()"
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
