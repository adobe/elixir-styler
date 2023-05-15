# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.PipesTest do
  use Styler.StyleCase, async: true

  describe "big picture" do
    test "case pipe" do
      assert_style """
      case foo do
        true -> :ok
        false -> :error
      end
      |> pipe()
      """,
      """
      if_result =
        if foo do
          :ok
        else
          :error
        end

      pipe(if_result)
      """
    end

    test "doesn't modify valid pipe" do
      assert_style("""
      a()
      |> b()
      |> c()

      a |> b() |> c()
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

    test "fixes nested pipes" do
      assert_style(
        """
        a
        |> e(fn x ->
          with({:ok, value} <- efoo(x), do: value)
          |> ebar()
          |> ebaz()
        end)
        |> b(fn x ->
          with({:ok, value} <- foo(x), do: value)
          |> bar()
          |> baz()
        end)
        |> c
        """,
        """
        a
        |> e(fn x ->
          with_result = with({:ok, value} <- efoo(x), do: value)

          with_result
          |> ebar()
          |> ebaz()
        end)
        |> b(fn x ->
          with_result = with({:ok, value} <- foo(x), do: value)

          with_result
          |> bar()
          |> baz()
        end)
        |> c()
        """
      )
    end
  end

  describe "block pipe starts" do
    test "variable assignment of a block" do
      assert_style(
        """
        x =
          case y do
            :ok -> :ok |> IO.puts()
          end
          |> bar()
          |> baz()
        """,
        """
        case_result =
          case y do
            :ok -> IO.puts(:ok)
          end

        x =
          case_result
          |> bar()
          |> baz()
        """
      )
    end

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

    test "rewrites unless" do
      assert_style(
        """
        unless foo do
          bar
        end
        |> wee()
        """,
        """
        unless_result =
          unless foo do
            bar
          end

        wee(unless_result)
        """
      )
    end

    test "rewrites with" do
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

    test "rewrites case" do
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

    test "rewrites if" do
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

  describe "single pipe issues" do
    test "fixes simple single pipes" do
      assert_style("b(a) |> c()", "a |> b() |> c()")
      assert_style("a |> f()", "f(a)")
      assert_style("x |> bar", "bar(x)")
      assert_style("def a, do: b |> c()", "def a, do: c(b)")
    end

    test "keeps invocation on a single line" do
      assert_style(
        """
        foo
        |> bar(baz, bop, boom)
        """,
        """
        bar(foo, baz, bop, boom)
        """
      )

      assert_style(
        """
        foo
        |> bar(baz)
        """,
        """
        bar(foo, baz)
        """
      )

      assert_style(
        """
        def halt(exec, halt_message) do
          %__MODULE__{exec | halted: true}
          |> put_halt_message(halt_message)
        end
        """,
        """
        def halt(exec, halt_message) do
          put_halt_message(%__MODULE__{exec | halted: true}, halt_message)
        end
        """
      )

      assert_style(
        """
        if true do
          false
        end
        |> foo(
          bar
        )
        """,
        """
        if_result =
          if true do
            false
          end

        foo(if_result, bar)
        """
      )
    end
  end

  describe "valid pipe starts" do
    test "allows fn" do
      assert_style("""
      fn
        :ok -> :ok
        :error -> :error
      end
      |> b()
      |> c()
      """)
    end

    test "recognizes infix ops as valid pipe starts" do
      assert_style("(bar() == 1) |> foo()", "foo(bar() == 1)")
      assert_style("(x in 1..100) |> foo()", "foo(x in 1..100)")
    end

    test "0 arity is just fine!" do
      assert_style("foo() |> bar() |> baz()")
      assert_style("Module.foo() |> bar() |> baz()")
    end

    test "ecto funtimes" do
      for from <- ~w(from Query.from Ecto.Query.from) do
        assert_style("""
        #{from}(foo in Bar, where: foo.bool)
        |> some_query_helper()
        |> Repo.all()
        """)
      end

      assert_style("^foo |> Ecto.Query.bar() |> Ecto.Query.baz()")
    end
  end

  describe "simple rewrites" do
    test "rewrites anon fun def ahd invoke to use then" do
      assert_style("a |> (& &1).()", "then(a, & &1)")
      assert_style("a |> (& {&1, &2}).(b)", "(&{&1, &2}).(a, b)")
      assert_style("a |> (& &1).() |> c", "a |> then(& &1) |> c()")

      assert_style("a |> (fn x, y -> {x, y} end).() |> c", "a |> then(fn x, y -> {x, y} end) |> c()")
      assert_style("a |> (fn x -> x end).()", "then(a, fn x -> x end)")
      assert_style("a |> (fn x -> x end).() |> c", "a |> then(fn x -> x end) |> c()")
    end

    test "adds parens to 1-arity pipes" do
      assert_style("a |> b |> c", "a |> b() |> c()")
    end

    test "reverse/concat" do
      assert_style("a |> Enum.reverse() |> Enum.concat()")
      assert_style("a |> Enum.reverse(bar) |> Enum.concat()")
      assert_style("a |> Enum.reverse(bar) |> Enum.concat(foo)")
      assert_style("a |> Enum.reverse() |> Enum.concat(foo)", "Enum.reverse(a, foo)")

      assert_style(
        """
        a
        |> Enum.reverse()
        |> Enum.concat([bar, baz])
        |> Enum.sum()
        """,
        """
        a
        |> Enum.reverse([bar, baz])
        |> Enum.sum()
        """
      )
    end

    test "filter/count" do
      assert_style(
        """
        a
        |> Enum.filter(fun)
        |> Enum.count()
        |> IO.puts()
        """,
        """
        a
        |> Enum.count(fun)
        |> IO.puts()
        """
      )

      assert_style(
        """
        a
        |> Enum.filter(fun)
        |> Enum.count()
        """,
        """
        Enum.count(a, fun)
        """
      )

      assert_style(
        """
        if true do
          []
        else
          [a, b, c]
        end
        |> Enum.filter(fun)
        |> Enum.count()
        """,
        """
        if_result =
          if true do
            []
          else
            [a, b, c]
          end

        Enum.count(if_result, fun)
        """
      )
    end

    test "map/join" do
      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.join("|")
        """,
        """
        Enum.map_join(a, "|", b)
        """
      )
    end

    test "map/into" do
      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.into(%{})
        """,
        "Map.new(a, b)"
      )

      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.into(Map.new())
        """,
        "Map.new(a, b)"
      )

      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.into(my_map)
        """,
        "Enum.into(a, my_map, b)"
      )

      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.into(%{some: :existing_map})
        """,
        "Enum.into(a, %{some: :existing_map}, b)"
      )

      assert_style(
        """
        a_multiline_mapper
        |> Enum.map(fn %{gets: shrunk, down: to_a_more_reasonable} ->
          IO.puts "woo!"
          {shrunk, to_a_more_reasonable}
        end)
        |> Enum.into(size)
        """,
        """
        Enum.into(a_multiline_mapper, size, fn %{gets: shrunk, down: to_a_more_reasonable} ->
          IO.puts("woo!")
          {shrunk, to_a_more_reasonable}
        end)
        """
      )
    end

    test "into a new map" do
      assert_style("a |> Enum.into(foo) |> b()")
      assert_style("a |> Enum.into(%{}) |> b()", "a |> Map.new() |> b()")
      assert_style("a |> Enum.into(Map.new) |> b()", "a |> Map.new() |> b()")

      assert_style("a |> Enum.into(foo, mapper) |> b()")
      assert_style("a |> Enum.into(%{}, mapper) |> b()", "a |> Map.new(mapper) |> b()")
      assert_style("a |> Enum.into(Map.new, mapper) |> b()", "a |> Map.new(mapper) |> b()")

      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.into(%{}, c)
        """,
        """
        a
        |> Enum.map(b)
        |> Map.new(c)
        """
      )

      assert_style(
        """
        a
        |> Enum.map(b)
        |> Enum.into(Map.new, c)
        """,
        """
        a
        |> Enum.map(b)
        |> Map.new(c)
        """
      )
    end
  end
end
