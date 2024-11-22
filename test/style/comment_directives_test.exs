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

    test "sorts lists" do
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
  end
end
