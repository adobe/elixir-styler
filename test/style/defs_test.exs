# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.DefsTest do
  use Styler.StyleCase, async: true

  test "comments stay put when we can't shrink the head, even with blocks" do
    assert_style("""
      def my_function(
          so_long_that_this_head_will_not_fit_on_one_lineso_long_that_this_head_will_not_fit_on_one_line,
          so_long_that_this_head_will_not_fit_on_one_line
        ) do
      result =
        case foo do
          :bar -> :baz
          :baz -> :bong
        end

      # My comment
      Context.process(result)
    end
    """)
  end

  test "function with do keyword" do
    assert_style(
      """
      # Top comment
      def save(
             # Socket comment
             %Socket{assigns: %{user: user, live_action: :new}} = initial_socket,
             # Params comment
             params
           ),
           do: :ok
      """,
      """
      # Top comment
      # Socket comment
      # Params comment
      def save(%Socket{assigns: %{user: user, live_action: :new}} = initial_socket, params), do: :ok
      """
    )
  end

  test "bodyless function with spec" do
    assert_style("""
    @spec original_object(atom()) :: atom()
    def original_object(object)
    """)
  end

  test "block function body doesn't get newlined" do
    assert_style("""
    # Here's a comment
    def some_function(%{id: id, type: type, processed_at: processed_at} = file, params, _)
        when type == :file and is_nil(processed_at) do
      with {:ok, results} <- FileProcessor.process(file) do
        # This comment could make sense
        {:ok, post_process_the_results_somehow(results)}
      end
    end
    """)
  end

  test "kwl function body doesn't get newlined" do
    assert_style("""
    def is_expired_timestamp?(timestamp) when is_integer(timestamp),
      do: Timex.from_unix(timestamp, :second) <= Timex.shift(DateTime.utc_now(), minutes: 1)
    """)
  end

  test "function with do block" do
    assert_style(
      """
      def save(
             %Socket{assigns: %{user: user, live_action: :new}} = initial_socket,
             params # Comments in the darndest places
           ) do
        :ok
      end
      """,
      """
      # Comments in the darndest places
      def save(%Socket{assigns: %{user: user, live_action: :new}} = initial_socket, params) do
        :ok
      end
      """
    )
  end

  test "no body" do
    assert_style "def no_body_nor_parens_yikes!"

    assert_style(
      """
      # Top comment
      def no_body(
        foo, # This is a foo
        bar  # This is a bar
      )

      # Another comment for this head
      def no_body(nil, _), do: nil
      """,
      """
      # Top comment
      # This is a foo
      # This is a bar
      def no_body(foo, bar)

      # Another comment for this head
      def no_body(nil, _), do: nil
      """
    )
  end

  test "when clause w kwl do" do
    assert_style(
      """
      def foo(%{
        bar: baz
        })
        # Self-documenting code!
        when baz in [
          :a, # Obviously, this is a
          :b  # ... and this is b
        ],
        do: :never_write_code_like_this
      """,
      """
      # Self-documenting code!
      # Obviously, this is a
      # ... and this is b
      def foo(%{bar: baz}) when baz in [:a, :b], do: :never_write_code_like_this
      """
    )
  end

  test "keyword do with a list" do
    assert_style(
      """
      def foo,
        do: [
          # Weirdo comment
          :never_write_code_like_this
        ]
      """,
      """
      # Weirdo comment
      def foo, do: [:never_write_code_like_this]
      """
    )
  end

  test "rewrites subsequent definitions" do
    assert_style(
      """
      def foo(), do: :ok

      def foo(
        too,
        # Long long is too long
        long
      ), do: :ok
      """,
      """
      def foo, do: :ok

      # Long long is too long
      def foo(too, long), do: :ok
      """
    )
  end

  test "when clause with block do" do
    assert_style(
      """
      # Foo takes a bar
      def foo(%{
        bar: baz
        })
        # Baz should be either :a or :b
        when baz in [
          :a,
          :b
        ]
        do # Weird place for a comment
        # Above the body
        :never_write_code_like_this
        # Below the body
      end
      """,
      """
      # Foo takes a bar
      # Baz should be either :a or :b
      # Weird place for a comment
      def foo(%{bar: baz}) when baz in [:a, :b] do
        # Above the body
        :never_write_code_like_this
        # Below the body
      end
      """
    )
  end

  test "Doesn't move stuff around if it would make the line too long" do
    assert_style("""
    @doc "this is a doc"
    # And also a comment
    def wow_this_function_name_is_super_long(it_also, has_a, ton_of, arguments),
      do: "this is going to end up making the line too long if we inline it"

    @doc "this is another function"
    # And it also has a comment
    def this_one_fits_on_one_line, do: :ok
    """)
  end

  test "Doesn't collapse pipe chains in a def do ... end" do
    assert_style("""
    def foo(some_list) do
      some_list
      |> Enum.reject(&is_nil/1)
      |> Enum.map(&transform/1)
    end
    """)
  end

  describe "no ops" do
    test "regression: @def module attribute" do
      assert_style("@def ~s(this should be okay)")
    end

    test "no explode on invalid def syntax" do
      assert_style("def foo, true")
      assert_style("def foo(a), true")
      assert_raise SyntaxError, fn -> assert_style("def foo(a) true") end
    end
  end
end
