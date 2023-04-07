# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.DefsTest do
  use Styler.StyleCase, style: Styler.Style.Defs, async: true

  describe "elixir ast dependencies we rely on" do
    test "def with do ... end block" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo(
          arg1
        )
        do
          :ok
        end
        """)

      # This structure is the same when the head is a single line or multiple
      # lines - it only changes the numbers in the metadata.
      assert {:def, def_meta, [head, _body]} = ast
      assert def_meta[:line] == 1
      assert def_meta[:do][:line] == 4
      assert def_meta[:end][:line] == 6

      assert {:foo, head_meta, [_arg_node]} = head
      assert head_meta[:line] == 1
      assert head_meta[:closing][:line] == 3
    end

    test "def with empty parens" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo(
        )
        do
          :ok
        end
        """)

      assert {:def, def_meta, [head, _body]} = ast
      assert def_meta[:line] == 1
      assert def_meta[:do][:line] == 3
      assert def_meta[:end][:line] == 5

      # Empty list here for args because there are none
      assert {:foo, head_meta, []} = head
      # but there is still metadata to describe the parens
      assert head_meta[:line] == 1
      assert head_meta[:closing][:line] == 2
    end

    test "def with no parens" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo do
          :ok
        end
        """)

      assert {:def, def_meta, [head, _body]} = ast
      assert def_meta[:line] == 1
      assert def_meta[:do][:line] == 1
      assert def_meta[:end][:line] == 3

      # nil for args and no `closing` meta since there are no parens
      assert {:foo, head_meta, nil} = head
      assert head_meta[:line] == 1
      refute head_meta[:closing]
    end

    test "def with a do: keyword and a simple body" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo,
          do: :ok
        """)

      # The Keyword form doesn't have `do` and `end` metadata
      assert {:def, def_meta, [_head, body]} = ast
      assert def_meta[:line] == 1
      refute def_meta[:do]
      refute def_meta[:end]

      # The body is a keyword list
      assert [
        {
          {:__block__, key_meta, [:do]},
          {:__block__, val_meta, [:ok]}
        }
      ] = body
      assert key_meta[:format] == :keyword
      assert key_meta[:line] == 2

      # Since there's no `closing` metadata, we can tell that it's a "simple" `do` expression
      assert val_meta[:line] == 2
      refute val_meta[:closing]
    end

    test "def with a do: keyword and multi-line body" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo,
          do: [
            1,
            2
          ]
        """)

      assert {:def, _meta, [_head, body]} = ast
      assert [
        {
          {:__block__, _, [:do]},
          {:__block__, val_meta, val}
        }
      ] = body

      # Since the value is a list, the meta tells us where it begins and ends,
      # and its child node is the actual list elements as a sub-list
      assert val_meta[:line] == 2
      assert val_meta[:closing][:line] == 5
      assert [[
        {:__block__, _, [1]},
        {:__block__, _, [2]}
      ]] = val
    end

    test "def with a do: keyword and multi-statement body" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo,
          do: (
            1;
            2
          )
        """)

      assert {:def, _meta, [_head, body]} = ast
      assert [
        {
          {:__block__, _, [:do]},
          {:__block__, val_meta, [one, two]}
        }
      ] = body

      # Block metadata works the same as a multi-line value
      assert val_meta[:line] == 2
      assert val_meta[:closing][:line] == 5

      assert {:__block__, _, [1]} = one
      assert {:__block__, _, [2]} = two
    end

    test "def with a guard clause and a do: block" do
      {ast, _comments} = Styler.string_to_quoted_with_comments("""
        def foo
        when is_nil(nil)
        when is_atom(nil),
        do: :ok
        """)

      # When clauses act like infix operators
      assert {:def, _, [{:when, _, [head , guards]}, body]} = ast
      # Head is still just a normal function head (with no parens)
      assert {:foo, _, nil} = head
      # Body is still just a normal keyword list
      assert [{
        {:__block__, _, [:do]},
        {:__block__, _, [:ok]}
      }] = body
      # This `when` is just another infix operartor so multiple `when` clauses nest in the AST
      # It works the same with `:or` or `:and` e.g. if you wrote `when guard1() and guard2()`
      assert {:when, _, [{:is_nil, _, _}, {:is_atom, _, _}]} = guards
    end
  end

  describe "run" do
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
        def foo(), do: :ok

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
      assert_style(
        """
        @doc "this is a doc"
        # And also a comment
        def wow_this_function_name_is_super_long(it_also, has_a, ton_of, arguments),
          do: "this is going to end up making the line too long if we inline it"

        @doc "this is another function"
        # And it also has a comment
        def this_one_fits_on_one_line, do: :ok
        """
      )
    end

    test "Doesn't collapse pipe chains in a def do ... end" do
      assert_style(
        """
        def foo(some_list) do
          some_list
          |> Enum.reject(&is_nil/1)
          |> Enum.map(&transform/1)
        end
        """
      )
    end
  end
end
