# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ModuleDirectives.AliasLiftingTest do
  @moduledoc false
  use Styler.StyleCase, async: true

  test "lifts aliases repeated >=2 times from 3 deep" do
    assert_style(
      """
      defmodule A do
        @moduledoc false

        @spec bar :: A.B.C.t()
        def bar do
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false

        alias A.B.C

        @spec bar :: C.t()
        def bar do
          C.f()
        end
      end
      """
    )
  end

  describe "it doesn't lift" do
    test "defprotocol, defmodule, or defimpl" do
      assert_style """
      defmodule No do
        @moduledoc false

        defprotocol A.B.C do
          :body
        end

        A.B.C.f()
      end
      """

      assert_style """
      defmodule No do
        @moduledoc false
        alias A.B.C

        defprotocol A.B.C do
          :body
        end

        C.f()
        C.f()
      end
      """

      assert_style """
      defmodule No do
        @moduledoc false

        defmodule A.B.C do
          @moduledoc false
          :body
        end

        A.B.C.f()
      end
      """

      assert_style """
      defmodule No do
        @moduledoc false

        defimpl A.B.C, for: A.B.C do
          :body
        end

        A.B.C.f()
      end
      """
    end

    test "quoted sections" do
      assert_style """
      defmodule A do
        @moduledoc false
        defmacro __using__(_) do
          quote do
            A.B.C.f()
            A.B.C.f()
          end
        end
      end
      """
    end
  end
end
