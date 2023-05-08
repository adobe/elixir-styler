# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.SimpleTest do
  use Styler.StyleCase, style: Styler.Style.Simple, async: true

  describe "numbers" do
    test "styles floats and integers with >4 digits" do
      assert_style(
        """
        10000
        1_0_0_0_0
        -543213
        123456789
        55333.22
        -123456728.0001
        """,
        """
        10_000
        10_000
        -543_213
        123_456_789
        55_333.22
        -123_456_728.0001
        """
      )
    end

    test "stays away from small numbers, strings and science" do
      assert_style("""
      1234
      9999
      "10000"
      0xFFFF
      0x123456
      0b1111_1111_1111_1111
      0o777_7777
      """)
    end
  end

  describe "Enum.reverse/1 and ++" do
    test "optimizes into `Enum.reverse/2`" do
      assert_style("Enum.reverse(foo) ++ bar", "Enum.reverse(foo, bar)")
      assert_style("Enum.reverse(foo, bar) ++ bar")
    end
  end
end
