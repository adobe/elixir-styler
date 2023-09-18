# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.SingleNodeTest do
  use Styler.StyleCase, async: true

  test "charlist literals: rewrites single quote charlists to ~c" do
    assert_style("'foo'", ~s|~c"foo"|)
    assert_style(~s|'"'|, ~s|~c"\\""|)
  end

  test "Logger.warn to Logger.warning" do
    assert_style("Logger.warn(foo)", "Logger.warning(foo)")
    assert_style("Logger.warn(foo, bar)", "Logger.warning(foo, bar)")
  end

  test "Timex.now => DateTime.utc_now/now!" do
    assert_style("Timex.now()", "DateTime.utc_now()")
    assert_style(~S|Timex.now("Some/Timezone")|, ~S|DateTime.now!("Some/Timezone")|)
  end

  test "Timex.today => Date.utc_today" do
    assert_style("Timex.today()", "Date.utc_today()")
    assert_style(~S|Timex.today("Some/Timezone")|, ~S|Timex.today("Some/Timezone")|)
  end

  if Version.match?(System.version(), ">= 1.15.0-dev") do
    test "{DateTime,NaiveDateTime,Time,Date}.compare to {DateTime,NaiveDateTime,Time,Date}.before?" do
      assert_style("DateTime.compare(foo, bar) == :lt", "DateTime.before?(foo, bar)")
      assert_style("NaiveDateTime.compare(foo, bar) == :lt", "NaiveDateTime.before?(foo, bar)")
      assert_style("Time.compare(foo, bar) == :lt", "Time.before?(foo, bar)")
      assert_style("Date.compare(foo, bar) == :lt", "Date.before?(foo, bar)")
    end

    test "{DateTime,NaiveDateTime,Time,Date}.compare to {DateTime,NaiveDateTime,Time,Date}.after?" do
      assert_style("DateTime.compare(foo, bar) == :gt", "DateTime.after?(foo, bar)")
      assert_style("NaiveDateTime.compare(foo, bar) == :gt", "NaiveDateTime.after?(foo, bar)")
      assert_style("Time.compare(foo, bar) == :gt", "Time.after?(foo, bar)")
      assert_style("Time.compare(foo, bar) == :gt", "Time.after?(foo, bar)")
    end
  end

  describe "def / defp" do
    test "0-arity functions have parens removed" do
      assert_style("def foo(), do: :ok", "def foo, do: :ok")
      assert_style("defp foo(), do: :ok", "defp foo, do: :ok")

      assert_style(
        """
        def foo() do
        :ok
        end
        """,
        """
        def foo do
          :ok
        end
        """
      )

      assert_style(
        """
        defp foo() do
        :ok
        end
        """,
        """
        defp foo do
          :ok
        end
        """
      )

      # Regression: be wary of invocations with extra parens from metaprogramming
      assert_style("def metaprogramming(foo)(), do: bar")
    end

    test "prefers implicit try" do
      for def_style <- ~w(def defp) do
        assert_style(
          """
          #{def_style} foo() do
            try do
              :ok
            rescue
              exception -> :excepted
            catch
              :a_throw -> :thrown
            else
              i_forgot -> i_forgot.this_could_happen
            after
              :done
            end
          end
          """,
          """
          #{def_style} foo do
            :ok
          rescue
            exception -> :excepted
          catch
            :a_throw -> :thrown
          else
            i_forgot -> i_forgot.this_could_happen
          after
            :done
          end
          """
        )
      end
    end

    test "doesnt rewrite when there are other things in the body" do
      assert_style("""
      def foo do
        try do
          :ok
        rescue
          exception -> :excepted
        end

        :after_try
      end
      """)
    end
  end

  describe "RHS pattern matching" do
    test "left arrows" do
      assert_style("with {:ok, result = %{}} <- foo, do: result", "with {:ok, %{} = result} <- foo, do: result")
      assert_style("for map = %{} <- maps, do: map[:key]", "for %{} = map <- maps, do: map[:key]")
    end

    test "case statements" do
      assert_style(
        """
        case foo do
          bar = %{baz: baz? = true} -> :baz?
          opts = [[a = %{}] | _] -> a
        end
        """,
        """
        case foo do
          %{baz: true = baz?} = bar -> :baz?
          [[%{} = a] | _] = opts -> a
        end
        """
      )
    end

    test "regression: ignores unquoted cases" do
      assert_style("case foo, do: unquote(quoted)")
    end

    test "removes a double-var assignment when one var is _" do
      assert_style("def foo(_ = bar), do: bar", "def foo(bar), do: bar")
      assert_style("def foo(bar = _), do: bar", "def foo(bar), do: bar")

      assert_style(
        """
        case foo do
          bar = _ -> :ok
        end
        """,
        """
        case foo do
          bar -> :ok
        end
        """
      )

      assert_style(
        """
        case foo do
          _ = bar -> :ok
        end
        """,
        """
        case foo do
          bar -> :ok
        end
        """
      )
    end

    test "defs" do
      assert_style(
        "def foo(bar = %{baz: baz? = true}, opts = [[a = %{}] | _]), do: :ok",
        "def foo(%{baz: true = baz?} = bar, [[%{} = a] | _] = opts), do: :ok"
      )
    end

    test "anon funs" do
      assert_style(
        "fn bar = %{baz: baz? = true}, opts = [[a = %{}] | _] -> :ok end",
        "fn %{baz: true = baz?} = bar, [[%{} = a] | _] = opts -> :ok end"
      )
    end

    test "leaves those poor case statements alone!" do
      assert_style("""
      cond do
        foo = Repo.get(Bar, 1) -> foo
        x == y -> :kaboom?
        true -> :else
      end
      """)
    end

    test "with statements" do
      assert_style(
        """
        with ok = :ok <- foo, :ok <- yeehaw() do
          ok
        else
          error = :error -> error
          other -> other
        end
        """,
        """
        with :ok = ok <- foo, :ok <- yeehaw() do
          ok
        else
          :error = error -> error
          other -> other
        end
        """
      )
    end
  end

  describe "numbers" do
    test "styles floats and integers with >4 digits" do
      assert_style("10000", "10_000")
      assert_style("1_0_0_0_0", "10_000")
      assert_style("-543213", "-543_213")
      assert_style("123456789", "123_456_789")
      assert_style("55333.22", "55_333.22")
      assert_style("-123456728.0001", "-123_456_728.0001")
    end

    test "stays away from small numbers, strings and science" do
      assert_style("1234")
      assert_style("9999")
      assert_style(~s|"10000"|)
      assert_style("0xFFFF")
      assert_style("0x123456")
      assert_style("0b1111_1111_1111_1111")
      assert_style("0o777_7777")
    end
  end

  describe "Enum.into and Map.new" do
    test "into a new map" do
      assert_style("Enum.into(a, foo)")
      assert_style("Enum.into(a, foo, mapper)")

      assert_style("Enum.into(a, %{})", "Map.new(a)")
      assert_style("Enum.into(a, Map.new)", "Map.new(a)")

      assert_style("Enum.into(a, %{}, mapper)", "Map.new(a, mapper)")
      assert_style("Enum.into(a, Map.new, mapper)", "Map.new(a, mapper)")
    end
  end

  describe "Enum.reverse/1 and ++" do
    test "optimizes into `Enum.reverse/2`" do
      assert_style("Enum.reverse(foo) ++ bar", "Enum.reverse(foo, bar)")
      assert_style("Enum.reverse(foo, bar) ++ bar")
    end
  end

  describe "case to if" do
    test "rewrites case true false to if else" do
      assert_style(
        """
        case foo do
          true -> :ok
          false -> :error
        end
        """,
        """
        if foo do
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          _ -> :error
        end
        """,
        """
        if foo do
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          false -> :error
          true -> :ok
        end
        """,
        """
        if foo do
          :ok
        else
          :error
        end
        """
      )

      assert_style(
        """
        case foo do
          true -> :ok
          false -> nil
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
  end

  describe "with statements" do
    test "doesn't false positive with vars" do
      assert_style("""
      if naming_is_hard, do: with
      """)
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
        else
          :error -> :error
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
        else
          :error -> :error
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
