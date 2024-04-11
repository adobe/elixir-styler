defmodule Styler.Dealias do
  @moduledoc """
  A datastructure for maintaining something like compiler alias state when traversing AST.

  Not anywhere as correct as what the compiler gives us, but close enough for open source work.
  """
  def new(aliases), do: Enum.reduce(aliases, %{}, &put(&2, &1))

  def put(dealiases, ast)
  def put(d, list) when is_list(list), do: Enum.reduce(list, d, &put(&2, &1))
  def put(d, {:alias, _, [{:__aliases__, _, aliases}]}), do: do_put(d, aliases, List.last(aliases))
  def put(d, {:alias, _, [{:__aliases__, _, aliases}, [{_as, {:__aliases__, _, [as]}}]]}), do: do_put(d, aliases, as)
  # `alias __MODULE__` or other oddities i'm not bothering to get right
  def put(dealiases, {:alias, _, _}), do: dealiases

  defp do_put(dealiases, modules, as) do
    Map.put(dealiases, as, do_dealias(dealiases, modules))
  end

  # no need to traverse ast if there are no aliases
  def apply(dealiases, ast) when map_size(dealiases) == 0, do: ast

  def apply(dealiases, {:alias, m, [{:__aliases__, m_, modules} | rest]}),
    do: {:alias, m, [{:__aliases__, m_, do_dealias(dealiases, modules)} | rest]}

  def apply(dealiases, ast) do
    Macro.prewalk(ast, fn
      {:__aliases__, meta, modules} -> {:__aliases__, meta, do_dealias(dealiases, modules)}
      ast -> ast
    end)
  end
  # if the list of modules is itself already aliased, dealias it with the compound alias
  # given:
  #   alias Foo.Bar
  #   Bar.Baz.Bop.baz()
  #
  # lifting Bar.Baz.Bop should result in:
  #   alias Foo.Bar
  #   alias Foo.Bar.Baz.Bop
  #   Bop.baz()
  defp do_dealias(dealiases, [first | rest] = modules) do
    if dealias = dealiases[first], do: dealias ++ rest, else: modules
  end
end
