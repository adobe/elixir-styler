# Copyright 2023 Adobe. All rights reserved.
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

  describe "with statements" do
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

      for nontrivial_head <- ["foo", ":ok = foo", ":ok <- foo, :ok <- bar"] do
        assert_style("""
        with #{nontrivial_head} do
          :success
        else
          :fail -> :failure
        end
        """)
      end
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
             {:ok, b} <- bar(a) do
          {:ok, b}
        else
          error -> error
        end
        """,
        """
        with {:ok, a} <- foo() do
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

  describe "if/else" do
    test "drops if else nil" do
      assert_style("if a, do: b, else: nil", "if a, do: b")

      assert_style("if a do b else nil end", """
      if a do
        b
      end
      """)
    end

    test "Credo.Check.Refactor.UnlessWithElse" do
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
    end

    test "Credo.Check.Refactor.NegatedConditionsInUnless" do
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
    end

    test "Credo.Check.Refactor.NegatedConditionsWithElse" do
      for negator <- ["!", "not "] do
        assert_style("if #{negator}foo, do: :bar")
        assert_style("if #{negator}foo, do: :bar, else: :baz", "if foo, do: :baz, else: :bar")

        assert_style("""
        if #{negator}foo do
          bar
        end
        """)

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
    end

    test "recurses" do
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
    end
  end
end
