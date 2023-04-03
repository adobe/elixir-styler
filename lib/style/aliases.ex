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

  def run({{:alias, _, _} = alias, %{l: left, r: right} = meta}) do
    {right, aliases} = consume_alias_group([alias | right], [])

    [last | rest] =
      aliases
      |> Enum.flat_map(&expand_alias/1)
      # Credo does case-agnostic sorting, so we have to match that here
      |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
      # a splash of deduping for happiness
      |> Enum.uniq_by(&elem(&1, 1))
      |> List.keysort(1, :desc)
      |> Enum.map(&(&1 |> elem(0) |> set_newlines(1)))

    {set_newlines(last, 2), %{meta | r: right, l: rest ++ left}}
  end

  def run(zipper), do: zipper

  # alias Foo.{Bar, Baz}
  # =>
  # alias Foo.Bar
  # alias Foo.Baz
  defp expand_alias({:alias, _, [{{:., _, [{_, _, module}, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} -> {:alias, meta, [{:__aliases__, [], module ++ segments}]} end)
  end

  defp expand_alias(alias), do: [alias]

  defp consume_alias_group([{:alias, meta, _} = alias | siblings], aliases) do
    if meta[:end_of_expression][:newlines] == 1 do
      consume_alias_group(siblings, [alias | aliases])
    else
      {siblings, [alias | aliases]}
    end
  end

  defp consume_alias_group(siblings, aliases), do: {siblings, aliases}

  defp set_newlines({node, meta, children}, newline) do
    updated_meta = Keyword.update(meta, :end_of_expression, [newlines: newline], &Keyword.put(&1, :newlines, newline))
    {node, updated_meta, children}
  end
end
