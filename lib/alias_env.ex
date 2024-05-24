defmodule Styler.AliasEnv do
  @moduledoc """
  A datastructure for maintaining something like compiler alias state when traversing AST.

  Not anywhere as correct as what the compiler gives us, but close enough for open source work.

  A alias env is a map from an alias's `as` to its resolution in a context.

  Given the ast for

      alias Foo.Bar

  we'd create the env:

      %{:Bar => [:Foo, :Bar]}
  """
  def define(env \\ %{}, ast)

  def define(env, asts) when is_list(asts), do: Enum.reduce(asts, env, &define(&2, &1))

  def define(env, {:alias, _, aliases}) do
    case aliases do
      [{:__aliases__, _, aliases}] -> define(env, aliases, List.last(aliases))
      [{:__aliases__, _, aliases}, [{_as, {:__aliases__, _, [as]}}]] -> define(env, aliases, as)
      # `alias __MODULE__` or other oddities i'm not bothering to get right
      _ -> env
    end
  end

  defp define(env, modules, as), do: Map.put(env, as, do_expand(env, modules))

  # no need to traverse ast if there are no aliases
  def expand(env, ast) when map_size(env) == 0, do: ast

  def expand(env, ast) do
    Macro.prewalk(ast, fn
      {:__aliases__, meta, modules} -> {:__aliases__, meta, do_expand(env, modules)}
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
  defp do_expand(env, [first | rest] = modules) do
    if dealias = env[first], do: dealias ++ rest, else: modules
  end
end
