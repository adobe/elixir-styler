# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.SingleNodeTest do
  use Styler.StyleCase, async: true

  test "string sigil rewrites" do
    assert_style ~s|""|
    assert_style ~s|"\\""|
    assert_style ~s|"\\"\\""|
    assert_style ~s|"\\"\\"\\""|
    assert_style ~s|"\\"\\"\\"\\""|, ~s|~s("""")|
    # choose closing delimiter wisely, based on what has the least conflicts, in the styliest order
    assert_style ~s/"\\"\\"\\"\\" )"/, ~s/~s{"""" )}/
    assert_style ~s/"\\"\\"\\"\\" })"/, ~s/~s|"""" })|/
    assert_style ~s/"\\"\\"\\"\\" |})"/, ~s/~s["""" |})]/
    assert_style ~s/"\\"\\"\\"\\" ]|})"/, ~s/~s'"""" ]|})'/
    assert_style ~s/"\\"\\"\\"\\" ']|})"/, ~s/~s<"""" ']|})>/
    assert_style ~s/"\\"\\"\\"\\" >']|})"/, ~s|~s/"""" >']\|})/|
    assert_style ~s/"\\"\\"\\"\\" \/>']|})"/, ~s|~s("""" />']\|}\\))|
  end

  test "{Map/Keyword}.merge with a single static key" do
    for module <- ~w(Map Keyword) do
      assert_style("#{module}.merge(foo, %{one_key: :bar})", "#{module}.put(foo, :one_key, :bar)")
      assert_style("#{module}.merge(foo, one_key: :bar)", "#{module}.put(foo, :one_key, :bar)")
      # # doesn't rewrite if there's a custom merge strategy
      assert_style("#{module}.merge(foo, %{one_key: :bar}, custom_merge_strategy)")
      # # doesn't rewrite if > 1 key
      assert_style("#{module}.merge(foo, %{a: :b, c: :d})")
    end
  end

  describe "Timex.now/0,1" do
    test "Timex.now/0 => DateTime.utc_now/0" do
      assert_style("Timex.now()", "DateTime.utc_now()")
      assert_style("Timex.now() |> foo() |> bar()", "DateTime.utc_now() |> foo() |> bar()")
    end

    test "Timex.now/1 => DateTime.now!/1" do
      assert_style("Timex.now(tz)", "DateTime.now!(tz)")

      assert_style(
        """
        timezone
        |> Timex.now()
        |> foo()
        """,
        """
        timezone
        |> DateTime.now!()
        |> foo()
        """
      )
    end
  end

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

  describe "Enum.into and $collectable.new" do
    test "into an empty map" do
      assert_style("Enum.into(a, %{})", "Map.new(a)")
      assert_style("Enum.into(a, %{}, mapper)", "Map.new(a, mapper)")
    end

    test "into a collectable" do
      assert_style("Enum.into(a, foo)")
      assert_style("Enum.into(a, foo, mapper)")

      for collectable <- ~W(Map Keyword MapSet), new = "#{collectable}.new" do
        assert_style("Enum.into(a, #{new})", "#{new}(a)")
        assert_style("Enum.into(a, #{new}, mapper)", "#{new}(a, mapper)")
      end
    end
  end

  describe "Enum.reverse/1 and ++" do
    test "optimizes into `Enum.reverse/2`" do
      assert_style("Enum.reverse(foo) ++ bar", "Enum.reverse(foo, bar)")
      assert_style("Enum.reverse(foo, bar) ++ bar")
    end
  end
end
