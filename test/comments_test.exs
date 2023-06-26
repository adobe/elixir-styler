defmodule Styler.CommentsTest do
  use ExUnit.Case, async: true

  alias Styler.Comments

  describe "preceding/2" do
    test "gets all comments" do
      {_, comments} =
        Styler.string_to_quoted_with_comments("""
        # not related

        # 1
        # 2
        some_code_on_line_5 # 3
        # nope
        """)

      assert [%{line: 3, text: "# 1"}, %{line: 4, text: "# 2"}, %{line: 5, text: "# 3"}] = Comments.preceding(comments, 5)
    end
  end
end
