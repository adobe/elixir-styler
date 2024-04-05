defmodule Styler.StyleTest do
  use ExUnit.Case, async: true

  import Styler.Style, only: [displace_comments: 2, shift_comments: 3]

  alias Styler.Style

  @code """
  # Above module
  defmodule Foo do
    # Top of module

    @moduledoc "This is a moduledoc"


    # Above spec
    @spec some_fun(
      atom()
    )
    :: atom()

    @doc "This is a function"
    # Above def
    def some_fun(
      # Before arg
      arg
      # After arg
    ) do
      # In function body
      :ok
    end

    # After def
  end
  # After module
  """

  @comments @code |> Styler.string_to_quoted_with_comments() |> elem(1)

  describe "displace_comments/2" do
    test "Doesn't lose any comments" do
      new_comments = displace_comments(@comments, 0..0)

      for comment <- @comments do
        assert Enum.any?(new_comments, &(&1.text == comment.text))
      end
    end

    test "Moves comments within the range to the start of the range" do
      # Sanity-check line numbers in test fixture
      before = [
        {"# Above def", 15},
        {"# Before arg", 17},
        {"# After arg", 19}
      ]

      for {text, line} <- before do
        assert line == Enum.find(@comments, &(&1.text == text)).line
      end

      # Simulate collapsing the `def` on lines 16-20
      new_comments = displace_comments(@comments, 16..20)

      expected = [
        {"# Above def", 15},
        {"# Before arg", 16},
        {"# After arg", 16}
      ]

      for {text, line} <- expected do
        assert line == Enum.find(new_comments, &(&1.text == text)).line
      end
    end
  end

  describe "shift_comments/3" do
    test "Doesn't lose any comments" do
      new_comments = shift_comments(@comments, 1..30, 1)

      for comment <- @comments do
        assert Enum.any?(new_comments, &(&1.text == comment.text))
      end
    end

    test "Moves comments after the specified line by the specified delta" do
      # Sanity-check line numbers in test fixture
      before = [
        {"# Above module", 1},
        {"# Top of module", 3},
        {"# Above def", 15},
        {"# In function body", 21},
        {"# After def", 25},
        {"# After module", 27}
      ]

      for {text, line} <- before do
        assert line == Enum.find(@comments, &(&1.text == text)).line
      end

      # Simulate collapsing the `def` on lines 16-20, shifting everything afterword up by 4
      new_comments = shift_comments(@comments, 21..23, -4)

      expected = [
        # Before 21 doesn't get moved
        {"# Above module", 1},
        {"# Top of module", 3},
        {"# Above def", 15},
        # 21 does get moved
        {"# In function body", 17},
        # After 23 doesn't get moved
        {"# After def", 25},
        {"# After module", 27}
      ]

      for {text, line} <- expected do
        assert line == Enum.find(new_comments, &(&1.text == text)).line
      end
    end
  end

  describe "fix_line_numbers" do
    test "returns ast list with increasing line numbers" do
      nodes = for n <- [1, 2, 999, 1000, 5, 6], do: {:node, [line: n], [n]}
      fixed = Style.fix_line_numbers(nodes, 7)

      Enum.scan(fixed, fn {_, [line: this_line], _} = this_node, {_, [line: previous_line], _} ->
        assert this_line >= previous_line
        this_node
      end)
    end
  end
end
