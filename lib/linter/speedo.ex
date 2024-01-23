defmodule Styler.Linter.Speedo do
  @moduledoc false

  alias Credo.Check.Consistency.ExceptionNames
  alias Credo.Check.Design.AliasUsage
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
    {name, m, args} = if name == :when, do: hd(args), else: {name, m, args}
    line = m[:line]
    name = to_string(name)
    error = %{file: ctx.file, line: line, check: nil, message: nil}

    snake_error =
      unless snake_case?(name), do: %{error | check: FunctionNames, message: "`#{def} #{name}` is not snake case"}

    predicate_error = %{error | check: PredicateFunctionNames, message: nil}

    predicate_error =
      cond do
        def in ~w(def defp)a and String.starts_with?(name, "is_") ->
          %{predicate_error | message: "`#{def} #{name}` is invalid -- use `?` not `is_` for defs"}

        def in ~w(defmacro defmacrop defguard defguardp)a and String.ends_with?(name, "?") ->
          %{predicate_error | message: "`#{def} #{name}`: use `is_*` not `*?` for things that can be used in guards"}

        true ->
          []
      end

    var_errors =
      Enum.map(args || [], fn arg ->
        {_, var_errors} = arg |> Zipper.zip() |> Zipper.traverse([], &readability_variable_names(&1, &2, ctx.file))
        var_errors
      end)

    ctx = Map.update!(ctx, :errors, &[snake_error, predicate_error, var_errors | &1])
    {zipper, ctx}
  end

  def run({{:defmodule, _, [{:__aliases__, m, aliases} | _]}, _} = zipper, ctx) do
    name = Enum.map_join(aliases, ".", &to_string/1)
    error = %{file: ctx.file, line: m[:line], check: nil, message: nil}

    pascal =
      unless pascal_case?(name),
        do: %{error | check: ModuleNames, message: "`defmodule #{inspect(name)}` is not pascal case"}

    module_body =
      zipper
      |> Zipper.down()
      |> Zipper.right()
      |> Zipper.down()
      |> Zipper.down()
      |> Zipper.right()

    module_children =
      case Zipper.node(module_body) do
        {:__block__, _, children} -> children
        # coerce single-child defmodules to have the same shape as multi-child
        {_, _, _} = only_child -> [only_child]
      end

    errors =
      Enum.flat_map(module_children, fn
        {:defexception, _, _} ->
          if String.ends_with?(name, "Error"),
            do: [],
            else: [%{error | check: ExceptionNames, message: "`#{name}`: exception modules must end in `Error`"}]

        {:@, m, [{:impl, _, [{:__block__, _, [true]}]}]} ->
          [%{error | line: m[:line], check: ImplTrue, message: "`@impl true` not allowed"}]

        {:@, _, [{name, m, _}]} ->
          if snake_case?(name),
            do: [],
            else: [%{error | line: m[:line], check: ModuleAttributeNames, message: "`@#{name}` is not snake case"}]

        _ ->
          []
      end)

    aliased =
      module_children
      |> Enum.flat_map(fn
        {:alias, _, [{:__aliases__, _, aliases}]} -> [aliases]
        _ -> []
      end)
      |> MapSet.new(&List.last/1)

    alias_errors =
      module_body
      |> Zipper.traverse(%{}, fn
        # A.B.C.f(...)
        {{{:., m, [{:__aliases__, _, [_, _, _ | _] = aliases}, _]}, _, _}, _} = zipper, acc ->
          {zipper, Map.update(acc, aliases, {false, m[:line]}, fn {_, l} -> {true, l} end)}

        zipper, acc ->
          {zipper, acc}
      end)
      |> elem(1)
      |> Enum.flat_map(fn
        {a, {true, l}} -> if List.last(a) in aliased, do: [], else: [%{error | line: l, check: AliasUsage, message: a}]
        _ -> []
      end)

    {zipper, Map.update!(ctx, :errors, &[[alias_errors, pascal | errors] | &1])}
  end

  def run({{:<-, m, [lhs, _] = args}, _} = zipper, ctx) do
    tag_error =
      case args do
        [{:__block__, _, [{{:__block__, _, [tag]}, _}]}, {:__block__, _, [{{:__block__, _, [tag]}, _}]}] ->
          msg = "tagging tuples with things like `#{inspect(tag)}` is known to be evil"
          %{file: ctx.file, line: m[:line], check: WithCustomTaggedTuple, message: msg}

        _ ->
          []
      end

    {_, assignment_errors} = lhs |> Zipper.zip() |> Zipper.traverse([], &readability_variable_names(&1, &2, ctx.file))
    {zipper, Map.update!(ctx, :errors, &[[tag_error | assignment_errors] | &1])}
  end

  # the `=` here will double report when nested in a case. need to move it to its own clause w/ "in block"
  def run({{assignment_op, _, [lhs, _]}, _} = zipper, ctx) when assignment_op in ~w(= ->)a do
    {_, errors} = lhs |> Zipper.zip() |> Zipper.traverse([], &readability_variable_names(&1, &2, ctx.file))
    {zipper, Map.update!(ctx, :errors, &[errors | &1])}
  end

  def run({{:__block__, [{:delimiter, ~s|"|} | _] = m, [string]}, _} = zipper, ctx) when is_binary(string) do
    if string =~ ~r/".*".*".*"/ do
      msg = "use a sigil for #{inspect(string)}, it has too many quotes"
      error = %{file: ctx.file, line: m[:line], check: StringSigils, message: msg}
      {zipper, Map.update!(ctx, :errors, &[error | &1])}
    else
      {zipper, ctx}
    end
  end

  def run(zipper, context), do: {zipper, context}

  defp readability_variable_names({{name, m, nil}, _} = zipper, errors, file) do
    if name in [:__CALLER__, :__DIR__, :__ENV__, :__MODULE__] or snake_case?(name) do
      {zipper, errors}
    else
      error = %{file: file, line: m[:line], check: VariableNames, message: to_string(name)}
      {zipper, [error | errors]}
    end
  end

  defp readability_variable_names(zipper, errors, _) do
    {zipper, errors}
  end

  defp snake_case?(name), do: to_string(name) =~ ~r/^[[:lower:]\d\_\!\?]+$/u
  defp pascal_case?(name), do: to_string(name) =~ ~r/^[A-Z][a-zA-Z0-9\.]*$/
end
