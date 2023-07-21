defmodule Styler.Style.BlocksTest do
  use Styler.StyleCase, async: true

  describe "run" do
    test "unless without else block" do
      assert_style(
        """
        unless allowed? do
          raise "Not allowed!"
        end
        """,
        """
        unless allowed? do
          raise "Not allowed!"
        end
        """
      )
    end

    test "unless with else block" do
      assert_style(
        """
        unless allowed? do
          raise "Not allowed!"
        else
          proceed_as_planned()
        end
        """,
        """
        if allowed? do
          proceed_as_planned()
        else
          raise "Not allowed!"
        end
        """
      )
    end
  end
end
