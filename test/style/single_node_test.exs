# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.SingleNodeTest do
  use Styler.StyleCase, style: Styler.Style.SingleNode, async: true

  describe "0-arity paren removal" do
    test "removes parens" do
      assert_style("def foo(), do: :ok", "def foo, do: :ok")
      assert_style("defp foo(), do: :ok", "defp foo, do: :ok")

      assert_style(
        """
        def foo() do
        :ok
        end
        """,
        """
        def foo do
          :ok
        end
        """
      )

      assert_style(
        """
        defp foo() do
        :ok
        end
        """,
        """
        defp foo do
          :ok
        end
        """
      )
    end
  end

  describe "implicit try" do
    test "rewrites functions whose only child is a try" do
      for def_style <- ~w(def defp) do
        assert_style(
          """
          #{def_style} foo() do
            try do
              :ok
            rescue
              exception -> :excepted
            catch
              :a_throw -> :thrown
            else
              i_forgot -> i_forgot.this_could_happen
            after
              :done
            end
          end
          """,
          """
          #{def_style} foo do
            :ok
          rescue
            exception -> :excepted
          catch
            :a_throw -> :thrown
          else
            i_forgot -> i_forgot.this_could_happen
          after
            :done
          end
          """
        )
      end
    end

    test "doesnt rewrite when there are other things in the body" do
      assert_style("""
      def foo do
        try do
          :ok
        rescue
          exception -> :excepted
        end

        :after_try
      end
      """)
    end
  end

  describe "numbers" do
    test "styles floats and integers with >4 digits" do
      assert_style("10000", "10_000")
      assert_style("1_0_0_0_0", "10_000")
      assert_style("-543213", "-543_213")
      assert_style("123456789", "123_456_789")
      assert_style("55333.22", "55_333.22")
      assert_style("-123456728.0001", "-123_456_728.0001")
    end

    test "stays away from small numbers, strings and science" do
      assert_style("1234")
      assert_style("9999")
      assert_style(~s|"10000"|)
      assert_style("0xFFFF")
      assert_style("0x123456")
      assert_style("0b1111_1111_1111_1111")
      assert_style("0o777_7777")
    end
  end

  describe "Enum.reverse/1 and ++" do
    test "optimizes into `Enum.reverse/2`" do
      assert_style("Enum.reverse(foo) ++ bar", "Enum.reverse(foo, bar)")
      assert_style("Enum.reverse(foo, bar) ++ bar")
    end
  end

  describe "case true false do" do
    test "rewrites case true false to if else" do
      assert_style(
        """
        case foo do
          true -> :ok
          false -> :error
        end
        """,
        """
        if foo do
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          _ -> :error
        end
        """,
        """
        if foo do
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          false -> :error
          true -> :ok
        end
        """,
        """
        if foo do
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          false -> nil
        end
        """,
        """
        if foo do
          :ok
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          _ -> nil
        end
        """,
        """
        if foo do
          :ok
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          false ->
            Logger.warn("it's false")
            nil
        end
        """,
        """
        if foo do
          :ok
        else
          Logger.warn("it's false")
          nil
        end
        """
      )
    end
  end
end
