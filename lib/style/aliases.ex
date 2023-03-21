# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Aliases do
  @moduledoc """
  Styles up aliases!

  This Style will expand multi-aliases and sort aliases within their groups.
  It also adds a newline after all alias groups.

  Rewrites for the following Credo rules:

    * `Credo.Check.Readability.AliasOrder`
    * `Credo.Check.Readability.MultiAlias`
    * `Credo.Check.Readability.UnnecessaryAliasExpansion`

  This module is more particular than credo for sorting. Notably, it sorts `alias __MODULE__`, whereas Credo allowed
  that alias intermixed anywhere in a group.
  """

  @behaviour Styler.Style

  alias Styler.Zipper

  def run({{:alias, _, _}, _} = zipper) do
    {zipper, aliases} =
      zipper
      |> Zipper.insert_left(:placeholder)
      |> consume_alias_group([])

    [first | rest] =
      aliases
      # Credo does case-agnostic sorting, so we have to match that here
      |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
      # a splash of deduping for happiness
      |> Enum.uniq_by(&elem(&1, 1))
      |> Enum.sort_by(&elem(&1, 1))
      |> Enum.map(&(&1 |> elem(0) |> set_newlines(1)))

    zipper =
      zipper
      |> Zipper.find(:prev, &(&1 == :placeholder))
      |> Zipper.replace(first)

    rest
    |> Enum.reduce(zipper, &(&2 |> Zipper.insert_right(&1) |> Zipper.right()))
    |> Zipper.update(&set_newlines(&1, 2))
  end

  def run(zipper), do: zipper

  defp set_newlines({node, meta, children}, newline) do
    meta = Keyword.update(meta, :end_of_expression, [newlines: newline], &Keyword.put(&1, :newlines, newline))
    {node, meta, children}
  end

  defp consume_alias_group({{:alias, meta, _} = alias, _} = zipper, aliases) do
    aliases = expand_alias(alias, aliases)
    zipper = Zipper.remove(zipper)

    # multiple newlines means this isn't a group. missing newline means EOF.
    # thus only when there's one newline do we continue accumulating for our alias group
    if meta[:end_of_expression][:newlines] == 1 do
      consume_alias_group(zipper, aliases)
    else
      {zipper, aliases}
    end
  end

  defp consume_alias_group(zipper, aliases) do
    # aliases in groups are always siblings, so we're using `Zipper.right` to save time from going down subtrees
    case Zipper.right(zipper) do
      nil -> {zipper, aliases}
      zipper -> consume_alias_group(zipper, aliases)
    end
  end

  # This is where multi alias expansion happens
  #
  # alias Foo.{Bar, Baz}
  # =>
  # alias Foo.Bar
  # alias Foo.Baz
  defp expand_alias({:alias, _, [{{:., _, [{_, _, module}, :{}]}, _, right}]}, aliases) do
    right
    |> Enum.map(fn {_, meta, segments} -> {:alias, meta, [{:__aliases__, [], module ++ segments}]} end)
    |> Enum.concat(aliases)
  end

  defp expand_alias({:alias, _, _} = alias, aliases), do: [alias | aliases]
end
