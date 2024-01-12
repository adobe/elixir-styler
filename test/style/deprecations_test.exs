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
  end

  if Version.match?(System.version(), ">= 1.16.0-dev") do
    test "File.stream!(path, modes, line_or_bytes) to File.stream!(path, line_or_bytes, modes)" do
      assert_style(
        "File.stream!(path, [encoding: :utf8, trim_bom: true], :line)",
        "File.stream!(path, :line, encoding: :utf8, trim_bom: true)"
      )
    end

    test "negative steps with Enum.slice/2" do
      assert_style("Enum.slice([1, 2, 3, 4], 1..-2)", "Enum.slice([1, 2, 3, 4], 1..-2//1)")
    end
  end
end
