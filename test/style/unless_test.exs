defmodule Styler.Style.UnlessTest do
  @moduledoc false
  use Styler.StyleCase, async: true

  describe "unless" do
    test "convert unless with else to if statement" do
      assert_style(
        """
        unless true do
          "this is a testing unless true path"
        else
          "this is a testing unless false path"
        end
        """,
        """
        if true do
          "this is a testing unless false path"
        else
          "this is a testing unless true path"
        end
        """
      )
    end

    test "convert unless with else to if statement with condition" do
      assert_style(
        """
        unless a == b do
          "this is a testing unless true path"
        else
          "this is a testing unless false path"
        end
        """,
        """
        if a == b do
          "this is a testing unless false path"
        else
          "this is a testing unless true path"
        end
        """
      )
    end

    test "skip unless without else statement" do
      assert_style("""
      unless true do
        "this is a testing unless true path"
      end
      """)
    end
  end

  describe "convert unless without else to if statement with inverted condition" do
    test "equal" do
      assert_style(
        """
        unless a == b do
          1
        end
        """,
        """
        if a != b do
          1
        end
        """
      )
    end

    test "not equal" do
      assert_style(
        """
        unless a != b, do: 1
        """,
        """
        if a == b, do: 1
        """
      )
    end

    test "greater" do
      assert_style(
        """
        unless a > b, do: 1
        """,
        """
        if a <= b, do: 1
        """
      )
    end

    test "greater equal" do
      assert_style(
        """
        unless a >= b, do: 1
        """,
        """
        if a < b, do: 1
        """
      )
    end

    test "less" do
      assert_style(
        """
        unless a < b, do: 1
        """,
        """
        if a >= b, do: 1
        """
      )
    end

    test "less equal" do
      assert_style(
        """
        unless a <= b, do: 1
        """,
        """
        if a > b, do: 1
        """
      )
    end
  end
end
