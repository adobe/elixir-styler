defmodule Styler.Linter.SpeedoTest do
  use Styler.LinterCase

  alias Credo.Check.Consistency.ExceptionNames
  alias Credo.Check.Readability.FunctionNames
  alias Credo.Check.Readability.ImplTrue
  alias Credo.Check.Readability.ModuleAttributeNames
  alias Credo.Check.Readability.ModuleNames
  alias Credo.Check.Readability.PredicateFunctionNames
  alias Credo.Check.Readability.VariableNames
  alias Credo.Check.Readability.WithCustomTaggedTuple

  describe "ExceptionNames" do
    test "meow" do
      assert_error "defmodule Foo, do: (defexception [:bar])", ExceptionNames
      refute_errors "defmodule FooError, do: (defexception [:bar])"
    end
  end

  describe "Credo.Check.Readability.FunctionNames" do
    test "positives" do
      for def <- ~w(def defp defmacro defmacrop defguard defguardp) do
        assert_error "#{def} ooF", FunctionNames
      end
    end

    test "negatives" do
      for def <- ~w(def defp defmacro defmacrop defguard defguardp) do
        refute_errors "#{def} snake(), do: :ok"
        refute_errors "#{def} snake_case(), do: :ok"
      end

      refute_errors "def unquote(foo)(), do: :ok"
    end
  end

  describe "Credo.Check.Readability.ImplTrue" do
    test "this one's pretty simple ngl" do
      assert_error(
        """
        defmodule Foo do
          @impl true
          def bar(), do: :ok
        end
        """,
        ImplTrue
      )

      refute_errors "defmodule Foo do @impl Blue end"
    end
  end

  describe "Credo.Check.Readability.ModuleAttributeNames" do
    test "snake s'il vous plaît" do
      assert_error "defmodule Foo do @weEeEe :foo end", ModuleAttributeNames
      refute_errors "defmodule Foo do @snake :always_snakey end"
      refute_errors "defmodule Foo do bar = @wEeEeE end"
    end
  end

  describe "Credo.Check.Readability.ModuleNames" do
    test "pascal por favor" do
      assert_error "defmodule Snake_Kinda do end", ModuleNames
      refute_errors "defmodule OkayName do end"
      refute_errors "defmodule Okay.Name do end"
    end
  end

  describe "Credo.Check.Readability.PredicateFunctionNames" do
    test "defs dont get `is_` prefix" do
      for def <- ~w(def defp) do
        assert_error "#{def} is_foo?", PredicateFunctionNames
        assert_error "#{def} is_foo?(bar)", PredicateFunctionNames
        assert_error "#{def} is_foo?(bar) when bar != :baz, do: :bop", PredicateFunctionNames
        refute_errors "#{def} foo?"
        refute_errors "#{def} foo?(bar)"
        refute_errors "#{def} foo?(bar) when bar != :baz, do: :bop"
      end
    end

    test "macros and guards dont get `?` suffix" do
      for def <- ~w(defmacro defmacrop defguard defguardp) do
        assert_error "#{def} is_foo?", PredicateFunctionNames
        assert_error "#{def} is_foo?(bar)", PredicateFunctionNames
        assert_error "#{def} is_foo?(bar) when bar != :baz, do: :bop", PredicateFunctionNames
        refute_errors "#{def} is_foo"
        refute_errors "#{def} is_foo(bar)"
        refute_errors "#{def} is_foo(bar) when bar != :baz, do: :bop"
      end
    end
  end

  describe "Credo.Check.Readability.VariableNames" do
    test "reports violations on variable creation only " do
      errors =
        lint("""
        def foo(badName) do
          with {:ok, anotherBadName} <- badName do
            [stopCamelCase | camelsTail] = anotherBadName
            lovely_var_name = functionNotYourFault()
          end
        end
        """)

      assert Enum.count(errors) == 4

      errors = errors |> Enum.group_by(& &1.line) |> Map.new()

      assert [%{check: VariableNames, message: "badName"}] = errors[1]
      assert [%{check: VariableNames, message: "anotherBadName"}] = errors[2]
      assert [one, two] = errors[3]
      assert "stopCamelCase" in [one.message, two.message]
      assert "camelsTail" in [one.message, two.message]
    end
  end

  describe "Credo.Check.Readability.WithCustomTaggedTuple" do
    test "shames tagged tuples" do
      assert_error "with {:ooph, result} <- {:ooph, call()}, do: :ok", WithCustomTaggedTuple
    end
  end
end
