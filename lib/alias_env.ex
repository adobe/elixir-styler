# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.AliasEnv do
  @moduledoc """
  A datastructure for maintaining something like compiler alias state when traversing AST.

  Not anywhere as correct as what the compiler gives us, but close enough for open source work.

  An alias env is a map from an alias's `as` to its resolution in a context.

  Given the ast for

      alias Foo.Bar

  we'd create the env:

      %{:Bar => [:Foo, :Bar]}
  """
  def define(env \\ %{}, ast)
  def define(env, asts) when is_list(asts), do: Enum.reduce(asts, env, &define(&2, &1))
  def define(env, {:alias, _, [{:__aliases__, _, aliases}]}), do: define(env, aliases, List.last(aliases))
  def define(env, {:alias, _, [{:__aliases__, _, aliases}, [{_, {:__aliases__, _, [as]}}]]}), do: define(env, aliases, as)
  # `alias __MODULE__` or other oddities i'm not bothering to get right
  def define(env, {:alias, _, _}), do: env

  defp define(env, modules, as), do: Map.put(env, as, expand(env, modules))

  @doc """
  Lengthens an alias to its full name, if its first name is defined in the environment"

  Useful for transforming the ast for code like:

      alias Bar.Baz.Foo #<- given the env with this alias
      Foo.Woo.Cool # <- ast

  to the ast for code like:

      alias Bar.Baz.Foo
      Bar.Baz.Foo.Woo.Cool
  """
  # no need to traverse ast if there are no aliases
  def expand_ast(env, ast) when map_size(env) == 0, do: ast

  def expand_ast(env, ast) do
    Macro.prewalk(ast, fn
      {:__aliases__, meta, modules} -> {:__aliases__, meta, expand(env, modules)}
      ast -> ast
    end)
  end

  @doc """
  Expands modules from env (wow that was helpful).

  Using the examples from `expand_ast`, this works roughly like so:

     > expand(%{Foo: [Bar, Baz, Foo]}, [Foo, Woo, Cool])
     => [Bar, Baz, Foo, Woo, Cool]
     > expand(%{}, [No, Alias, For, Me])
     => [No, Alias, For, Me]
  """
  def expand(env, [first | rest] = modules) do
    if dealias = env[first], do: dealias ++ rest, else: modules
  end

  @doc """
  An inverted AliasEnv is useful for translating a module to its alias, if one existed in the env

  In the case that a module is aliased multiple times, the inverted env will only keep the final alias as lexically sorted
  """
  def invert(env) do
    # It's a bit of a bummer to do the extra group_by out of caution that this 1-off mistake happens,
    # but ultimately we're usually working with a small list so performance costs are negligible
    env
    |> Enum.group_by(fn {_, v} -> v end, fn {k, _} -> k end)
    |> Map.new(fn
      {modules, [as]} ->
        {modules, as}

      # someone has something goofy going on, aliasing the same module with multiple names
      # alias A.B.C
      # alias A.B.C, as: Bar
      # alias A.B.C, as: Foo
      # we'll choose the one that comes last lexically, which will be the alpha-sorted last entry that isn't the default as
      {modules, multiple_as} ->
        default_as = List.last(modules)
        # being clever - rather than rejecting the default up front and doing an extra list-traversal,
        # just sort things and if the default comes first, grab the second element
        case Enum.sort(multiple_as, :desc) do
          [^default_as, last_as | _] -> {modules, last_as}
          [last_as | _] -> {modules, last_as}
        end
    end)
  end
end
