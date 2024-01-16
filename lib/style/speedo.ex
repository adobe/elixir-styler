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
  def run({{def, _, [{name, m, args} | _]}, _} = zipper, ctx) when def in @definer and is_atom(name) do
    line = m[:line]
    name = to_string(name)
    error = %{file: ctx.file, line: line, check: nil, message: nil}

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

    var_errors =
      Enum.map(args || [], fn arg ->
        {_, var_errors} = arg |> Zipper.zip() |> Zipper.traverse([], &find_vars_with_bad_names(&1, &2, ctx.file))
        var_errors
      end)

    ctx = Map.update!(ctx, :errors, &[snake_error, predicate_error, var_errors | &1])
    {zipper, ctx}
  end

  # Credo.Check.Readability.ModuleNames
  def run({{:defmodule, _, [{:__aliases__, m, aliases} | _]}, _} = zipper, ctx) do
    name = Enum.map_join(aliases, ".", &to_string/1)
    error = %{file: ctx.file, line: m[:line], check: nil, message: nil}

    pascal =
      unless pascal_case?(name),
        do: %{error | check: ModuleNames, message: "`defmodule #{inspect(name)}` is not pascal case"}

    errors =
      zipper
      |> Zipper.down()
      |> Zipper.right()
      |> Zipper.down()
      |> Zipper.down()
      |> Zipper.right()
      |> Zipper.children()
      |> Enum.flat_map(fn
        {:defexception, _, _} ->
          if String.ends_with?(name, "Error"),
            do: [],
            else: [
              %{
                error
                | check: Credo.Check.Consistency.ExceptionNames,
                  message: "`#{name}`: exception modules must end in `Error`"
              }
            ]

        {:@, _, [{:impl, m, [true]}]} ->
          [%{error | line: m[:line], check: ImplTrue, message: "`@impl true` not allowed"}]

        {:@, _, [{name, m, _}]} ->
          if snake_case?(name),
            do: [],
            else: [%{error | line: m[:line], check: ModuleAttributeNames, message: "`@#{name}` is not snake case"}]

        _ ->
          []
      end)

    {zipper, Map.update!(ctx, :errors, &[[pascal | errors] | &1])}
  end

  # Credo.Check.Readability.VariableNames
  # the `=` here will double report when nested in a case. need to move it to its own clause w/ "in block"
  def run({{assignment_op, _, [lhs, _]}, _} = zipper, ctx) when assignment_op in ~w(= <- ->)a do
    {_, errors} = lhs |> Zipper.zip() |> Zipper.traverse([], &find_vars_with_bad_names(&1, &2, ctx.file))
    {zipper, Map.update!(ctx, :errors, &[errors | &1])}
  end

  def run(zipper, context) do
    case run!(Zipper.node(zipper), context.file) do
      nil -> {zipper, context}
      [] -> {zipper, context}
      errors -> {zipper, Map.update!(context, :errors, &[errors | &1])}
    end
  end

  defp find_vars_with_bad_names({{name, m, nil}, _} = zipper, errors, file) do
    if name in [:__CALLER__, :__DIR__, :__ENV__, :__MODULE__] or snake_case?(name) do
      {zipper, errors}
    else
      error = %{file: file, line: m[:line], check: VariableNames, message: to_string(name)}
      {zipper, [error | errors]}
    end
  end

  defp find_vars_with_bad_names(zipper, errors, _) do
    {zipper, errors}
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

  @badName :bad
  def naughtyFun(naughtyParam) do
    IO.inspect(@badName)

    naughtyAssignment = :ok

    with {:ugh, naughtyVar} <- {:ugh, naughtyParam} do
      naughtyVar
    end
  end

  def foo(naughtyParam2, %{bar: :x = naughtyParam3}) do
  end

  defexception [:foo]

  defp snake_case?(name), do: to_string(name) =~ ~r/^[[:lower:]\d\_\!\?]+$/u
  defp pascal_case?(name), do: to_string(name) =~ ~r/^[A-Z][a-zA-Z0-9\.]*$/
end
