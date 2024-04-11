defmodule Styler.Dealias do
  def new(aliases), do: Enum.reduce(aliases, %{}, &put(&2, &1))

  def put(dealiases, ast)
  def put(d, {:alias, _, [{:__aliases__, _, aliases}]}), do: do_put(d, aliases, List.last(aliases))
  def put(d, {:alias, _, [{:__aliases__, _, aliases}, [{_as, {:__aliases__, _, [as]}}]]}), do: do_put(d, aliases, as)
  # `alias __MODULE__` or other oddities i'm not bothering to get right
  def put(dealiases, {:alias, _, _}), do: dealiases

  defp do_put(dealiases, [first | rest] = modules, as) do
    modules = if dealias = dealiases[first], do: dealias ++ rest, else: modules
    Map.put(dealiases, as, modules)
  end
end
