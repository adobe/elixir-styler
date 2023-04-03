# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ModuleDirectivesTest do
  use Styler.StyleCase, style: Styler.Style.ModuleDirectives, async: true

  describe "run/1" do
    test "sorts, dedupes & expands alias/require/import while respecting groups" do
      for d <- ~w(alias require import) do
        assert_style(
          """
          #{d} D
          #{d} A.{B}
          #{d} A.{
            A,
            B,
            C
          }
          #{d} A.B

          #{d} B
          #{d} A
          """,
          """
          #{d} A.A
          #{d} A.B
          #{d} A.C
          #{d} D

          #{d} A
          #{d} B
          """
        )
      end
    end

    test "expands use but does not sort it" do
      assert_style(
        """
        use D
        use A.{
          C,
          B
        }
        """,
        """
        use D

        use A.C
        use A.B
        """
      )
    end

    test "interwoven alias requires" do
      assert_style(
        """
        alias D
        alias A.{B}
        require A.{
          A,
          C
        }
        alias B
        alias A
        """,
        """
        alias A.B
        alias D

        require A.A
        require A.C

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
