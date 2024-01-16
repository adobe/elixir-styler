defmodule Styler.Speedo do
  @moduledoc false

  alias Credo.Check.Readability.FunctionNames
  alias Credo.Check.Readability.ImplTrue
  alias Credo.Check.Readability.ModuleAttributeNames
  alias Credo.Check.Readability.ModuleNames
  alias Credo.Check.Readability.PredicateFunctionNames
  alias Credo.Check.Readability.StringSigils
  alias Credo.Check.Readability.VariableNames
  alias Credo.Check.Readability.WithCustomTaggedTuple
  alias Styler.Zipper

  def run(zipper, context) do
    case run!(Zipper.node(zipper), context.file) do
      nil -> {zipper, context}
      [] -> {zipper, context}
      errors -> {zipper, Map.update!(context, :errors, &[errors | &1])}
    end
  end

  @definer ~w(def defp defmacro defmacrop defguard defguardp)a
  defp run!({def, _, [{name, m, _} | _]}, file) when def in @definer do
    line = m[:line]
    name = to_string(name)
    # Credo.Check.Readability.FunctionNames
    snake_error =
      unless snake_case?(name), do: %{file: file, check: FunctionNames, message: "#{def} #{name} is not snake case"}

    predicate_error = %{file: file, line: line, check: PredicateFunctionNames, message: nil}
    # Credo.Check.Readability.PredicateFunctionNames
    predicate_error =
      cond do
        String.starts_with?(name, "is_") && String.ends_with?(name, "?") ->
          [%{predicate_error | message: "#{def} #{name} wow choose `?` or `is_`, you monster"}]

        def in ~w(def defp)a and String.starts_with?(name, "is_") ->
          [%{predicate_error | message: "#{def} #{name} is invalid -- use `?` not `is_` for defs"}]

        def in ~w(defmacro defmacrop defguard defguardp)a and String.ends_with?(name, "?") ->
          [%{predicate_error | message: "#{def} #{name}: use `is_*` not `*?` for things that can be used in guards"}]

        true ->
          []
      end

    [snake_error | predicate_error]
  end

  # Credo.Check.Readability.ImplTru
  defp run!({:@, _, [{:impl, m, [true]}]}, file),
    do: %{file: file, line: m[:line], check: ImplTrue, message: "`@impl true` not allowed"}
  # Credo.Check.Readability.ModuleAttributeNames
  defp run!({:@, _, [{name, m, _}]}, file) do
    unless snake_case?(name),
      do: %{file: file, line: m[:line], check: ModuleAttributeNames, message: "@#{name} is not snake case"}
  end

  # Credo.Check.Readability.ModuleNames
  defp run!({:defmodule, _, [{:__aliases__, m, aliases} | _]}, file) do
    name = Enum.map_join(aliases, ".", &to_string/1)

    unless pascal_case?(name),
      do: %{file: file, line: m[:line], check: ModuleNames, message: "defmodule #{name} is not pascal case"}
  end

  # Credo.Check.Readability.StringSigils
  defp run!({:__block__, [{:delimiter, ~s|"|} | _] = m, [string]}, file) do
    if string =~ ~r/".*".*"/ do
      msg = "use a sigil for #{inspect(string)}, it has too many quotes"
      %{file: file, line: m[:line], check: StringSigils, message: msg}
    end
  end

  # Credo.Check.Readability.VariableNames
  defp run!({name, m, nil}, file) do
    # probably get false positives here if people haven't run their pipes thru first
    # also, when we start reporting multiple errors this'll need updating to only report at the place a var is created 🤔
    unless snake_case?(name),
      do: %{file: file, line: m[:line], check: VariableNames, message: "#{name}: variables must be snake case"}
  end

  # Credo.Check.Readability.WithCustomTaggedTuple
  defp run!({:<-, m, [{tag, _}, {tag, _}]}, file) do
    msg = "tagging tuples with things like #{tag} is known to be evil"
    %{file: file, line: m[:line], check: WithCustomTaggedTuple, message: msg}
  end

  #
  # def naughtyFun do
  #   raise "nooooo"
  # end

  defp snake_case?(name), do: to_string(name) =~ ~r/^[[:lower:]\d\_\!\?]+$/u
  defp pascal_case?(name), do: to_string(name) =~ ~r/^[A-Z][a-zA-Z0-9]*$/
end
