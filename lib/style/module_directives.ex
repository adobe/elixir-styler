# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ModuleDirectives do
  @moduledoc """
  Styles up module directives!

  This Style will expand multi-aliases/requires/imports/use and sort the directive within its groups (except `use`s, which cannot be sorted)
  It also adds a blank line after each directive group.

  Rewrites for the following Credo rules:

    * `Credo.Check.Consistency.MultiAliasImportRequireUse` (force expansion)
    * `Credo.Check.Readability.AliasOrder`
    * `Credo.Check.Readability.MultiAlias`
    * `Credo.Check.Readability.UnnecessaryAliasExpansion`

  This module is more particular than credo for sorting. Notably, it sorts `alias __MODULE__`, whereas Credo allowed
  that alias intermixed anywhere in a group.
  """
  @behaviour Styler.Style

  @directives ~w(use import require alias)a

  def run({{d, _, _} = directive, %{l: left, r: right} = meta}) when d in @directives do
    {right, directives} = consume_directive_group(d, [directive | right], [])

    directives = Enum.flat_map(directives, &expand_directive/1)

    [last | rest ] =
      if d == :use do
        # don't sort `use` since it's side-effecting
        Enum.reverse(directives)
      else
        directives
        # Credo does case-agnostic sorting, so we have to match that here
        |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
        # a splash of deduping for happiness
        |> Enum.uniq_by(&elem(&1, 1))
        |> List.keysort(1, :desc)
        |> Enum.map(&(&1 |> elem(0) |> set_newlines(1)))
      end

    {set_newlines(last, 2), %{meta | r: right, l: rest ++ left}}
  end

  def run(zipper), do: zipper

  # alias Foo.{Bar, Baz}
  # =>
  # alias Foo.Bar
  # alias Foo.Baz
  defp expand_directive({directive, _, [{{:., _, [{_, _, module}, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} -> {directive, meta, [{:__aliases__, [], module ++ segments}]} end)
  end

  defp expand_directive(alias), do: [alias]

  defp consume_directive_group(d, [{d, meta, _} = directive | siblings], directives) do
    if d != :use and meta[:end_of_expression][:newlines] == 1 do
      consume_directive_group(d, siblings, [directive | directives])
    else
      {siblings, [directive | directives]}
    end
  end

  defp consume_directive_group(_, siblings, directives), do: {siblings, directives}

  defp set_newlines({directive, meta, children}, newline) do
    updated_meta = Keyword.update(meta, :end_of_expression, [newlines: newline], &Keyword.put(&1, :newlines, newline))
    {directive, updated_meta, children}
  end
end
