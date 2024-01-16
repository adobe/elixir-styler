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

  @definer ~w(def defp defmacro defmacrop defguard defguardp)a
  def run({{def, _, [{name, m, _} | _]}, _} = zipper, context) when def in @definer and is_atom(name) do
    line = m[:line]
    name = to_string(name)
    error = %{file: context.file, line: line, check: nil, message: nil}

    snake_error =
      unless snake_case?(name), do: %{error | check: FunctionNames, message: "`#{def} #{name}` is not snake case"}

    predicate_error = %{error | check: PredicateFunctionNames, message: nil}

    predicate_error =
      cond do
        String.starts_with?(name, "is_") && String.ends_with?(name, "?") ->
          %{predicate_error | message: "`#{def} #{name}` wow choose `?` or `is_`, you monster"}

        def in ~w(def defp)a and String.starts_with?(name, "is_") ->
          %{predicate_error | message: "`#{def} #{name}` is invalid -- use `?` not `is_` for defs"}

        def in ~w(defmacro defmacrop defguard defguardp)a and String.ends_with?(name, "?") ->
          %{predicate_error | message: "`#{def} #{name}`: use `is_*` not `*?` for things that can be used in guards"}

        true ->
          []
      end

    context = Map.update!(context, :errors, &[snake_error, predicate_error | &1])
    {zipper, context}
  end

  # Credo.Check.Readability.VariableNames
  def run({{name, m, nil}, _} = zipper, ctx) do
    # probably get false positives here if people haven't run their pipes thru first
    # also, when we start reporting multiple errors this'll need updating to only report at the place a var is created 🤔
    error =
      if not Styler.Style.in_block?(zipper) or snake_case?(name) or
           name in [:__STACKTRACE__, :__CALLER__, :__DIR__, :__ENV__, :__MODULE__] do
        []
      else
        %{file: ctx.file, line: m[:line], check: VariableNames, message: "`#{name}`: variables must be snake case"}
      end

    ctx = Map.update!(ctx, :errors, &[error | &1])
    {zipper, ctx}
  end

  def run(zipper, context) do
    case run!(Zipper.node(zipper), context.file) do
      nil -> {zipper, context}
      [] -> {zipper, context}
      errors -> {zipper, Map.update!(context, :errors, &[errors | &1])}
    end
  end

  # Credo.Check.Readability.ImplTru
  defp run!({:@, _, [{:impl, m, [true]}]}, file),
    do: %{file: file, line: m[:line], check: ImplTrue, message: "`@impl true` not allowed"}

  # Credo.Check.Readability.ModuleAttributeNames
  defp run!({:@, _, [{name, m, _}]}, file) do
    unless snake_case?(name),
      do: %{file: file, line: m[:line], check: ModuleAttributeNames, message: "`@#{inspect(name)}` is not snake case"}
  end

  # Credo.Check.Readability.ModuleNames
  defp run!({:defmodule, _, [{:__aliases__, m, aliases} | _]}, file) do
    name = Enum.map_join(aliases, ".", &to_string/1)

    unless pascal_case?(name),
      do: %{file: file, line: m[:line], check: ModuleNames, message: "`defmodule #{inspect(name)}` is not pascal case"}
  end

  # Credo.Check.Readability.StringSigils
  defp run!({:__block__, [{:delimiter, ~s|"|} | _] = m, [string]}, file) when is_binary(string) do
    if string =~ ~r/".*".*"/ do
      msg = "use a sigil for #{inspect(string)}, it has too many quotes"
      %{file: file, line: m[:line], check: StringSigils, message: msg}
    end
  end

  # Credo.Check.Readability.WithCustomTaggedTuple
  defp run!(
         {:<-, m, [{:__block__, _, [{{:__block__, _, [tag]}, _}]}, {:__block__, _, [{{:__block__, _, [tag]}, _}]}]},
         file
       ) do
    msg = "tagging tuples with things like `#{inspect(tag)}` is known to be evil"
    %{file: file, line: m[:line], check: WithCustomTaggedTuple, message: msg}
  end

  defp run!(_, _), do: []

  def naughtyFun(naughtyVar) do
    with {:ugh, naughty_var} <- {:ugh, naughtyVar} do
      naughty_var
    end
  end

  defp snake_case?(name), do: to_string(name) =~ ~r/^[[:lower:]\d\_\!\?]+$/u
  defp pascal_case?(name), do: to_string(name) =~ ~r/^[A-Z][a-zA-Z0-9\.]*$/
end
