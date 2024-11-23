# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.CommentDirectivesTest do
  @moduledoc false
  use Styler.StyleCase, async: true

  describe "sort" do
    test "we dont just sort by accident" do
      assert_style "[:c, :b, :a]"
    end

    test "sorts lists of atoms" do
      assert_style(
        """
        # styler:sort
        [
          :c,
          :b,
          :a
        ]
        """,
        """
        # styler:sort
        [
          :a,
          :b,
          :c
        ]
        """
      )
    end

    test "sorts sigils" do
      assert_style("# styler:sort\n~w|c a b|", "# styler:sort\n~w|a b c|")

      assert_style(
        """
        # styler:sort
        ~w(
          a
          long
          list
          of
          static
          values
        )
        """,
        """
        # styler:sort
        ~w(
          a
          list
          long
          of
          static
          values
        )
        """
      )
    end

    test "assignments" do
      assert_style(
        """
        # styler:sort
        my_var =
          ~w(
            a
            long
            list
            of
            static
            values
          )
        """,
        """
        # styler:sort
        my_var =
          ~w(
            a
            list
            long
            of
            static
            values
          )
        """
      )

      assert_style(
        """
        defmodule M do
          @moduledoc false
          # styler:sort
          @attr ~w(
              a
              long
              list
              of
              static
              values
            )
        end
        """,
        """
        defmodule M do
          @moduledoc false
          # styler:sort
          @attr ~w(
              a
              list
              long
              of
              static
              values
            )
        end
        """
      )
    end

    test "doesnt affect downstream nodes" do
      assert_style(
        """
        # styler:sort
        [:c, :a, :b]

        @country_codes ~w(
          po_PO
          en_US
          fr_CA
          ja_JP
        )
        """,
        """
        # styler:sort
        [:a, :b, :c]

        @country_codes ~w(
          po_PO
          en_US
          fr_CA
          ja_JP
        )
        """
      )
    end
  end
end
