# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.PipesTest do
  use Styler.StyleCase, style: Styler.Style.Pipes, async: true

  describe "block starts" do
    test "rewrites fors" do
      assert_style(
        """
        for(a <- as, do: a)
        |> bar()
        |> baz()
        """,
        """
        for_result = for(a <- as, do: a)

        for_result
        |> bar()
        |> baz()
        """
      )
    end

    test "rewrites blocks" do
      assert_style(
        """
        with({:ok, value} <- foo(), do: value)
        |> bar()
        |> baz()
        """,
        """
        with_result = with({:ok, value} <- foo(), do: value)

        with_result
        |> bar()
        |> baz()
        """
      )
    end

    test "rewrites conds" do
      assert_style(
        """
        cond do
          x -> :ok
          true -> :error
        end
        |> bar()
        |> baz()
        """,
        """
        cond_result =
          cond do
            x -> :ok
            true -> :error
          end

        cond_result
        |> bar()
        |> baz()
        """
      )
    end

    test "rewrites case at root" do
      assert_style(
        """
        case x do
          x -> x
        end
        |> foo()
        """,
        """
        case_result =
          case x do
            x -> x
          end

        foo(case_result)
        """
      )
    end

    test "single pipe of case w/ parent" do
      assert_style(
        """
        def foo do
          case x do
            x -> x
          end
          |> foo()
        end
        """,
        """
        def foo do
          case_result =
            case x do
              x -> x
            end

          foo(case_result)
        end
        """
      )
    end
  end

  describe "run on single pipe + start issues" do
    test "anon functio is finen" do
      assert_style("""
      fn
        :ok -> :ok
        :error -> :error
      end
      |> b()
      |> c()
      """)
    end

    test "handles that weird single pipe but with function call" do
      assert_style("b(a) |> c()", "a |> b() |> c()")
    end

    test "doesn't modify valid pipe" do
      assert_style("""
      a()
      |> b()
      |> c()

      a |> b() |> c()
      """)
    end
  end

  describe "run on single pipe issues" do
    test "fixes single pipe" do
      assert_style("a |> f()", "f(a)")
    end

    test "fixes single pipe in function head" do
      assert_style(
        """
        def a, do: b |> c()
        """,
        """
        def a, do: c(b)
        """
      )
    end

    test "extracts blocks successfully" do
      assert_style(
        """
        def foo do
          if true do
            nil
          end
          |> a()
          |> b()
        end
        """,
        """
        def foo do
          if_result =
            if true do
              nil
            end

          if_result
          |> a()
          |> b()
        end
        """
      )
    end
  end

  describe "run on pipe chain start issues" do
    test "allows 0-arity function calls" do
      assert_style("""
      foo()
      |> bar()
      |> baz()
      """)
    end

    test "allows ecto's from" do
      assert_style("""
      from(foo in Bar, where: foo.bool)
      |> some_query_helper()
      |> Repo.all()
      """)
    end

    test "extracts >0 arity functions" do
      assert_style(
        """
        M.f(a, b)
        |> g()
        |> h()
        """,
        """
        a
        |> M.f(b)
        |> g()
        |> h()
        """
      )
    end
  end
end
