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

  describe "run" do
    test "function with do keyword" do
      assert_style(
        """
        def save(
               %Socket{assigns: %{user: user, live_action: :new}} = initial_socket,
               params
             ),
             do: :ok
        """,
        """
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
      def some_function(%{id: id, type: type, processed_at: processed_at} = file, params, _)
          when type == :file and is_nil(processed_at) do
        with {:ok, results} <- FileProcessor.process(file) do
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
               params
             ) do
          :ok
        end
        """,
        """
        def save(%Socket{assigns: %{user: user, live_action: :new}} = initial_socket, params) do
          :ok
        end
        """
      )
    end

    test "no body" do
      assert_style(
        """
        def no_body(
          foo,
          bar
        )

        def no_body(nil, _), do: nil
        """,
        """
        def no_body(foo, bar)

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
          when baz in [
            :a,
            :b
          ],
          do: :never_write_code_like_this
        """,
        """
        def foo(%{bar: baz}) when baz in [:a, :b], do: :never_write_code_like_this
        """
      )
    end

    test "rewrites subsequent definitions" do
      assert_style(
        """
        def foo(), do: :ok

        def foo(
          too,
          long
        ), do: :ok
        """,
        """
        def foo(), do: :ok

        def foo(too, long), do: :ok
        """
      )
    end

    test "when clause with block do" do
      assert_style(
        """
        def foo(%{
          bar: baz
          })
          when baz in [
            :a,
            :b
          ]
          do
          :never_write_code_like_this
        end
        """,
        """
        def foo(%{bar: baz}) when baz in [:a, :b] do
          :never_write_code_like_this
        end
        """
      )
    end
  end
end
