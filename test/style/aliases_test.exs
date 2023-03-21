# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.AliasesTest do
  use Styler.StyleCase, style: Styler.Style.Aliases, async: true

  describe "run/1" do
    test "sorts, dedupes & expands aliases while respecting groups" do
      assert_style(
        """
        alias D
        alias A.{B}
        alias A.{
          A,
          B,
          C
        }
        alias A.B

        alias B
        alias A
        """,
        """
        alias A.A
        alias A.B
        alias A.C
        alias D

        alias A
        alias B
        """
      )
    end

    test "respects as" do
      assert_style("""
      alias Foo.Asset
      alias Foo.Project.Loaders, as: ProjectLoaders
      alias Foo.ProjectDevice.Loaders, as: ProjectDeviceLoaders
      alias Foo.User.Loaders
      """)
    end
  end
end
