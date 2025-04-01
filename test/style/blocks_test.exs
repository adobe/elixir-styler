# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.BlocksTest do
  use Styler.StyleCase, async: true

  describe "case to if" do
    test "rewrites case true false to if else" do
      assert_style(
        """
        case foo do
          # a
          true -> :ok
          # b
          false -> :error
        end
        """,
        """
        if foo do
          # a
          :ok
        else
          # b
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          # a
          true -> :ok
          # b
          _ -> :error
        end
        """,
        """
        if foo do
          # a
          :ok
        else
          # b
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          # a
          true -> :ok
          # b
          false -> nil
        end
        """,
        """
        if foo do
          # a
          :ok
        end

        # b
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          _ -> nil
        end
        """,
        """
        if foo do
          :ok
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          false ->
            Logger.warning("it's false")
            nil
        end
        """,
        """
        if foo do
          :ok
        else
          Logger.warning("it's false")
          nil
        end
        """
      )
    end

    test "block swapping comments" do
      assert_style(
        """
        case foo do
          false ->
            # a
            :error
          true ->
            # b
            :ok
        end
        """,
        """
        if foo do
          # b
          :ok
        else
          # a
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          # a
          false ->
            :error
          # b
          true ->
            :ok
        end
        """,
        """
        if foo do
          # b
          :ok
        else
          # a
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          # a
          false -> :error
          # b
          true -> :ok
        end
        """,
        """
        if foo do
          # b
          :ok
        else
          # a
          :error
        end
        """
      )
    end

    test "complex comments" do
      assert_style(
        """
        case foo do
          false ->
            #a
            actual(code)

            #b
            if foo do
              #c
              doing_stuff()
              #d
            end

            #e
            :ok
          true ->
            #f
            Logger.warning("it's false")

            if 1 do
              # g
              :yay
            else
              # h
              :ohno
            end

            # i
            nil
        end
        """,
        """
        if foo do
          # f
          Logger.warning("it's false")

          if 1 do
            # g
            :yay
          else
            # h
            :ohno
          end

          # i
          nil
        else
          # a
          actual(code)

          # b
          if foo do
            # c
            doing_stuff()
            # d
          end

          # e
          :ok
        end
        """
      )
    end
  end

  describe "with" do
    test "replacement due to no (or all removed) arrows" do
      assert_style(
        """
        x()

        z =
          with a <- b(), c <- d(), e <- f() do
            g
          else
            _ -> h
          end

        y()
        """,
        """
        x()

        z =
          (
            a = b()
            c = d()
            e = f()
            g
          )

        y()
        """
      )

      assert_style(
        """
        with a <- b(), c <- d(), e <- f() do
          g
        else
          _ -> h
        end
        """,
        """
        a = b()
        c = d()
        e = f()
        g
        """
      )

      assert_style(
        """
        x()

        with a <- b(), c <- d(), e <- f() do
          g
        else
          _ -> h
        end

        y()
        """,
        """
        x()

        a = b()
        c = d()
        e = f()
        g
        y()
        """
      )

      assert_style(
        """
        def run() do
          with value <- arg do
            value
          end
        end
        """,
        """
        def run do
          arg
        end
        """
      )

      assert_style(
        """
        fn ->
          with value <- arg do
            value
          end
        end
        """,
        """
        fn ->
          arg
        end
        """
      )

      assert_style(
        """
        foo(with a <- b(), c <- d(), e <- f() do
          g
        else
          _ -> h
        end)
        """,
        """
        foo(
          (
            a = b()
            c = d()
            e = f()
            g
          )
        )
        """
      )

      assert_style(
        """
        with a <- b(c), {:ok, result} <- x(y, z), do: {:ok, result}
        """,
        """
        a = b(c)
        x(y, z)
        """
      )

      assert_style(
        """
        with x = y, a = b do
          w
          z
        else
         _ -> whatever
        end
        """,
        """
        x = y
        a = b
        w
        z
        """
      )

      assert_style "with do: x", "x"
      assert_style "with do x end", "x"
      assert_style "with do x else foo -> bar end", "x"
      assert_style "with foo() do bar() else _ -> baz() end", "foo()\nbar()"
    end

    test "doesn't false positive with vars" do
      assert_style("""
      if naming_is_hard, do: with
      """)
    end

    test "removes identity else clauses" do
      assert_style(
        """
        with :ok <- b(), :ok <- b() do
          weeee()
          :ok
        else
          :what -> :what
        end
        """,
        """
        with :ok <- b(), :ok <- b() do
          weeee()
          :ok
        end
        """
      )
    end

    test "Credo.Check.Readability.WithSingleClause" do
      assert_style(
        """
        with :ok <- foo do
          :success
        else
          error = :error -> error
          :fail -> :failure
        end
        """,
        """
        case foo do
          :ok -> :success
          :error = error -> error
          :fail -> :failure
        end
        """
      )

      for nontrivial_head <- [":ok <- foo, :ok <- bar"] do
        assert_style("""
        with #{nontrivial_head} do
          :success
        else
          :fail -> :failure
        end
        """)
      end

      assert_style("with :ok <- foo(), do: :ok", "foo()")
    end

    test "rewrites non-pattern-matching lhs" do
      assert_style(
        """
        with foo <- bar,
             :ok <- baz,
             bop <- boop,
             :ok <- blop,
             foo <- bar do
          :ok
        end
        """,
        """
        foo = bar

        with :ok <- baz,
             bop = boop,
             :ok <- blop do
          foo = bar
          :ok
        end
        """
      )
    end

    test "doesn't move keyword do up when it's just one line" do
      assert_style("""
      with :ok <- foo(),
           do: :error
      """)
    end

    test "rewrites `_ <- rhs` to just rhs" do
      assert_style(
        """
        with _ <- bar,
             :ok <- baz,
             _ <- boop(),
             :ok <- blop,
             _ <- bar do
          :ok
        end
        """,
        """
        bar

        with :ok <- baz,
             boop(),
             :ok <- blop do
          bar
          :ok
        end
        """
      )
    end

    test "transforms a `with` all the way to an `if` if necessary" do
      # with a preroll
      assert_style(
        """
        with foo <- bar,
          true <- bop do
          :ok
        else
          _ -> :error
        end
        """,
        """
        foo = bar

        if bop do
          :ok
        else
          :error
        end
        """
      )

      # no pre or postroll
      assert_style(
        """
        with true <- bop do
          :ok
        else
          _ -> :error
        end
        """,
        """
        if bop do
          :ok
        else
          :error
        end
        """
      )

      # with postroll
      assert_style(
        """
        with true <- bop, foo <- bar do
          :ok
        else
          _ -> :error
        end
        """,
        """
        if bop do
          foo = bar
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        with true <- foo do
          boop
          bar
        end
        """,
        """
        if foo do
          boop
          bar
        end
        """
      )

      assert_style "with true <- x, do: bar", "if x, do: bar"

      assert_style(
        """
        with true <- foo || {:error, :shouldve_used_an_if_statement} do
          bar
        end
        """,
        """
        if foo do
          bar
        else
          {:error, :shouldve_used_an_if_statement}
        end
        """
      )
    end

    test "switches keyword do to block do when adding postroll" do
      assert_style(
        """
        with {:ok, _} <- foo(),
             _ <- bar(),
             do: :ok
        """,
        """
        with {:ok, _} <- foo() do
          bar()
          :ok
        end
        """
      )
    end

    test "regression: no weird parens" do
      assert_style(
        """
        foo = bar()

        with bop <- baz(),
             {:ok, _} <- woo() do
          :ok
        end
        """,
        """
        foo = bar()

        bop = baz()

        with {:ok, _} <- woo() do
          :ok
        end
        """
      )

      assert_style(
        """
        with :ok <- foo,
             bar <- bar() do
          query =
            bar
            |> prepare_query()
            |> select([rt], fragment("count(*)"))

          if opts[:dry_run] do
            {:ok, bar, query}
          else
            DB.Repo.one(query, timeout: bar["timeout"])
          end
        end
        """,
        """
        with :ok <- foo do
          bar = bar()

          query =
            bar
            |> prepare_query()
            |> select([rt], fragment(\"count(*)\"))

          if opts[:dry_run] do
            {:ok, bar, query}
          else
            DB.Repo.one(query, timeout: bar[\"timeout\"])
          end
        end
        """
      )
    end

    test "regression: non-block bodies and postrolls" do
      assert_style(
        """
        with {:ok, datetime, 0} <- DateTime.from_iso8601(dt),
           shifted_datetime <- DateTime.shift_zone!(datetime, full_name) do
          Calendar.strftime(shifted_datetime, "%Y/%m/%d - %I:%M %p")
        end
        """,
        """
        with {:ok, datetime, 0} <- DateTime.from_iso8601(dt) do
          shifted_datetime = DateTime.shift_zone!(datetime, full_name)
          Calendar.strftime(shifted_datetime, \"%Y/%m/%d - %I:%M %p\")
        end
        """
      )
    end

    test "moves non-arrow clauses from the beginning & end" do
      assert_style(
        """
        with foo, bar, :ok <- baz, :ok <- boz, a = bop, boop do
          :horay!
        else
          :error -> :error
        end
        """,
        """
        foo
        bar

        with :ok <- baz, :ok <- boz do
          a = bop
          boop
          :horay!
        end
        """
      )

      assert_style(
        """
        with :ok <- baz, :ok <- boz, a = bop, boop do
          :horay!
        else
          :error -> :error
        end
        """,
        """
        with :ok <- baz, :ok <- boz do
          a = bop
          boop
          :horay!
        end
        """
      )
    end

    test "Credo.Check.Refactor.RedundantWithClauseResult" do
      assert_style(
        """
        with {:ok, a} <- foo(),
             x = y,
             {:ok, b} <- bar(a) do
          {:ok, b}
        else
          error -> error
        end
        """,
        """
        with {:ok, a} <- foo() do
          x = y
          bar(a)
        end
        """
      )

      assert_style("""
      with {:ok, a} <- foo(),
           {:ok, b} <- bar(a) do
        {:ok, b}
      else
        error -> handle(error)
      end
      """)
    end

    test "with comments" do
      assert_style(
        """
        with :ok <- foo(),
            :ok <- bar(),
            # comment 1
            # comment 2
            # comment 3
            _ <- bop() do
          :ok
        end
        """,
        """
        with :ok <- foo(),
             :ok <- bar() do
          # comment 1
          # comment 2
          # comment 3
          bop()
          :ok
        end
        """
      )
    end

    test "skips with statements with no `do` block" do
      assert_style """
      def example_input(app_id, identifier) do
        with {:ok, _} <- function_one(app_id, identifier)

        {:ok, _} <-
          function_two(app_id, identifier) do
            :ok
          end
      end
      """
    end

    test "elixir1.17+ stab regressions" do
      assert_style(
        """
        with :ok <- foo, do: :bar, else: (_ -> :baz)
        """,
        """
        case foo do
          :ok -> :bar
          _ -> :baz
        end
        """
      )
    end
  end

  test "Credo.Check.Refactor.CondStatements" do
    for truthy <- ~w(true :atom :else) do
      assert_style(
        """
        cond do
          a -> b
          #{truthy} -> c
        end
        """,
        """
        if a do
          b
        else
          c
        end
        """
      )
    end

    for falsey <- ~w(false nil) do
      assert_style("""
      cond do
        a -> b
        #{falsey} -> c
      end
      """)
    end

    for ignored <- ["x == y", "foo", "foo()", "foo(b)", "Module.foo(x)", ~s("else"), "%{}", "{}"] do
      assert_style("""
      cond do
        a -> b
        #{ignored} -> c
      end
      """)
    end
  end

  describe "unless to if" do
    test "inverts all the things" do
      assert_style(
        """
        unless !! not true do
          a
        else
          b
        end
        """,
        """
        if true do
          a
        else
          b
        end
        """
      )

      for negator <- ["!", "not "] do
        assert_style(
          """
          unless #{negator} a do
            b
          else
            c
          end
          """,
          """
          if a do
            b
          else
            c
          end
          """
        )
      end

      for negator <- ["!=", "!=="], inverse = String.replace(negator, "!", "=") do
        assert_style(
          """
          unless x #{negator} y do
            b
          else
            c
          end
          """,
          """
          if x #{inverse} y do
            b
          else
            c
          end
          """
        )
      end

      assert_style(
        """
        unless a do
          b
        else
          c
        end
        """,
        """
        if a do
          c
        else
          b
        end
        """
      )

      for negator <- ["!", "not "] do
        assert_style("unless #{negator} foo, do: :bar", "if foo, do: :bar")

        assert_style(
          """
          unless #{negator} foo do
            bar
          end
          """,
          """
          if foo do
            bar
          end
          """
        )
      end

      for negator <- ["!=", "!=="], inverse = String.replace(negator, "!", "=") do
        assert_style("unless a #{negator} b, do: :bar", "if a #{inverse} b, do: :bar")

        assert_style(
          """
          unless a #{negator} b do
            c
          end
          """,
          """
          if a #{inverse} b do
            c
          end
          """
        )
      end
    end

    test "unless with pipes" do
      assert_style "unless a |> b() |> c(), do: x", "if !(a |> b() |> c()), do: x"
    end

    test "in" do
      assert_style "unless a in b, do: x", "if a not in b, do: x"
    end
  end

  describe "if" do
    test "drops else nil" do
      assert_style("if a, do: b, else: nil", "if a, do: b")

      assert_style("if a do b else nil end", """
      if a do
        b
      end
      """)

      assert_style(
        """
        if a != b do
          # comment
        else
          :ok
        end
        """,
        """
        if a == b do
          # comment
          :ok
        end
        """
      )
    end

    test "inverts do nil" do
      assert_style("if a, do: b, else: nil", "if a, do: b")

      assert_style("if a do nil else b end", """
      if !a do
        b
      end
      """)

      assert_style(
        """
        if a == b do
          # comment
        else
          :ok
        end
        """,
        """
        if a != b do
          # comment
          :ok
        end
        """
      )
    end

    test "double negator rewrites" do
      for a <- ~w(not !), block <- ["do: z", "do: z, else: zz"] do
        assert_style "if #{a} (x != y), #{block}", "if x == y, #{block}"
        assert_style "if #{a} (x !== y), #{block}", "if x === y, #{block}"
        assert_style "if #{a} ! x, #{block}", "if x, #{block}"
        assert_style "if #{a} not x, #{block}", "if x, #{block}"
      end

      assert_style("if not x, do: y", "if not x, do: y")
      assert_style("if !x, do: y", "if !x, do: y")

      assert_style(
        """
        if !!val do
          a
        else
          b
        end
        """,
        """
        if val do
          a
        else
          b
        end
        """
      )
    end

    test "single negator do/else swaps" do
      # covers Credo.Check.Refactor.NegatedConditionsWithElse
      for negator <- ["!", "not "] do
        assert_style("if #{negator}foo, do: :bar, else: :baz", "if foo, do: :baz, else: :bar")

        assert_style(
          """
          if #{negator}foo do
            bar
          else
            baz
          end
          """,
          """
          if foo do
            baz
          else
            bar
          end
          """
        )
      end

      for negator <- ["!=", "!=="], inverse = String.replace(negator, "!", "=") do
        assert_style("if a #{negator} b, do: :bar, else: :baz", "if a #{inverse} b, do: :baz, else: :bar")

        assert_style(
          """
          if a #{negator} b do
            bar
          else
            baz
          end
          """,
          """
          if a #{inverse} b do
            baz
          else
            bar
          end
          """
        )
      end
    end

    test "comments and flips" do
      assert_style(
        """
        if !a do
          # b
          b
        else
          # c
          c
        end
        """,
        """
        if a do
          # c
          c
        else
          # b
          b
        end
        """
      )
    end
  end
end
