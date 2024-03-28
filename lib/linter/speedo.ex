defmodule Styler.Linter.Speedo do
  @moduledoc false

  alias Credo.Check.Consistency.ExceptionNames
  alias Credo.Check.Readability.FunctionNames
  alias Credo.Check.Readability.ImplTrue
  alias Credo.Check.Readability.ModuleAttributeNames
  alias Credo.Check.Readability.ModuleNames
  alias Credo.Check.Readability.PredicateFunctionNames
  alias Credo.Check.Readability.VariableNames
  alias Credo.Check.Readability.WithCustomTaggedTuple
  alias Styler.Zipper

  @definer ~w(def defp defmacro defmacrop defguard defguardp)a
  def run({{def, _, [{name, m, args} | _]}, _} = zipper, ctx) when def in @definer and is_atom(name) do
    {name, m, args} = if name == :when, do: hd(args), else: {name, m, args}

    # :when clause means this might not be an atom :/
    name_errors =
      if is_atom(name) do
        error = %{file: ctx.file, line: m[:line], check: nil, message: nil}
        name = to_string(name)

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

        [snake_error, predicate_error]
      end

    var_errors =
      Enum.map(args || [], fn arg ->
        {_, var_errors} = arg |> Zipper.zip() |> Zipper.traverse([], &readability_variable_names(&1, &2, ctx.file))
        var_errors
      end)

    ctx = Map.update!(ctx, :errors, &[name_errors, var_errors | &1])
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

    {zipper, Map.update!(ctx, :errors, &[pascal, errors | &1])}
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
