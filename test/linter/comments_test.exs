defmodule Styler.Linter.CommentsTest do
  use ExUnit.Case, async: true

  import ExUnit.CaptureIO


  alias Styler.Linter.Comments

  alias Credo.Check.Foo.Bar

  defp parse_code(code) do
    {_, comments} = Styler.string_to_quoted_with_comments(code)
    Comments.parse(comments)
  end

  describe "parse" do
    test "ignores invalid" do
      assert [] =
               parse_code("""
               # woof
               # meow
               # credo:invalid
               """)
    end

    test "warns for disallowed credo features" do
      assert capture_io(fn ->
        assert [] = parse_code("# credo:disable-for-previous-line")
      end) =~ "invalid config `disable-for-previous-line`"
    end

    test "disable for this file" do
      assert [{:*, :*}] = parse_code("# credo:disable-for-this-file")
      assert [{:*, :*}] = parse_code("# credo:disable-for-this-file    ")
      assert [{Bar, :*}] = parse_code("# credo:disable-for-this-file  Credo.Check.Foo.Bar  ")
      assert [] = parse_code("# credo:disable-for-this-file   F ")
    end

    test "next line" do
      assert [{:*, 2}, {Bar, 5}] = parse_code("""
      # credo:disable-for-next-line
      two
      three
      # credo:disable-for-next-line Credo.Check.Foo.Bar
      five
      """)
    end

    test "lines" do
      assert [{:*, 2..4}, {Bar, 5..8}] = parse_code("""
      # credo:disable-for-lines:3
      two
      three
      # credo:disable-for-lines:4 Credo.Check.Foo.Bar
      five
      """)

      assert capture_io(fn ->
        assert [] = parse_code("# credo:disable-for-lines:-4 Credo.Check.Foo.Bar")
      end) =~ "credo:disable-for-lines with negative number ignored"
    end
  end
end
