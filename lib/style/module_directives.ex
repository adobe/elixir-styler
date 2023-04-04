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

  @directives ~w(alias import require)a

  @moduledoc_false {:@, [], [{:moduledoc, [], [{:__block__, [], [false]}]}]}

  def run({{:defmodule, def_meta, [name, [{mod_do, {:__block__, children_meta, children}}]]}, zipper_meta}) do
    {directives, other} =
      Enum.split_with(children, fn
        {:@, _, [{:moduledoc, _, _}]} -> true
        {directive, _, _} -> directive in [:use | @directives]
        _ -> false
      end)

    directives =
      Enum.group_by(directives, fn
        {:@, _, [{attr_name, _, _}]} -> :"@#{attr_name}"
        {directive, _, _} -> directive
      end)

    # TODO: (optimization)
    # now that we have use/import/alias/require, we might as well run
    # them through the sort/expand/dedupe functionality and skip them in the traversal
    moduledoc = directives[:"@moduledoc"] || [@moduledoc_false]
    uses = directives[:use] || []
    imports = directives[:import] || []
    aliases = directives[:alias] || []
    requires = directives[:require] || []

    children =
      Enum.concat([
        moduledoc,
        uses,
        imports,
        aliases,
        requires,
        other
      ])

    {{:defmodule, def_meta, [name, [{mod_do, {:__block__, children_meta, children}}]]}, zipper_meta}
  end

  # a module whose only child is a moduledoc. pass it on through
  def run({{:defmodule, _, [_, [{_, {:@, _, [{:moduledoc, _, _}]}}]]}, _} = zipper), do: zipper

  def run({{:defmodule, def_meta, [name, [{mod_do, mod_child}]]}, zipper_meta} = zipper) do
    # a module with a single child. lets add moduledoc false
    # ... unless it's a `defmodule Foo, do: ...`, that is
    {_, do_meta, _} = mod_do

    if do_meta[:format] == :keyword do
      zipper
    else
      IO.puts("needs moduledoc")
      # @TODO copy the line meta from mod_child to @moduledoc_false?
      mod_children =
        {:__block__, [],
         [
           @moduledoc_false,
           mod_child
         ]}

      {{:defmodule, def_meta, [name, [{mod_do, mod_children}]]}, zipper_meta}
    end
  end

  def run({{:use, _, _} = directive, meta}) do
    [last | rest] = directive |> expand_directive() |> Enum.reverse()
    meta = %{meta | l: rest ++ meta.l}

    case meta.r do
      [{:use, _, _} | _] -> {last, meta}
      _ -> {set_newlines(last, 2), meta}
    end
  end

  def run({{d, _, _} = directive, %{l: left, r: right} = meta}) when d in @directives do
    {right, directives} = consume_directive_group(d, [directive | right], [])

    [last | rest] =
      directives
      # Credo does case-agnostic sorting, so we have to match that here
      |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
      # a splash of deduping for happiness
      |> Enum.uniq_by(&elem(&1, 1))
      |> List.keysort(1, :desc)
      |> Enum.map(&(&1 |> elem(0) |> set_newlines(1)))

    {set_newlines(last, 2), %{meta | r: right, l: rest ++ left}}
  end

  def run(zipper), do: zipper

  defp consume_directive_group(d, [{d, meta, _} = directive | siblings], directives) do
    directives = expand_directive(directive) ++ directives

    if meta[:end_of_expression][:newlines] == 1,
      do: consume_directive_group(d, siblings, directives),
      else: {siblings, directives}
  end

  defp consume_directive_group(_, siblings, directives), do: {siblings, directives}

  # alias Foo.{Bar, Baz}
  # =>
  # alias Foo.Bar
  # alias Foo.Baz
  defp expand_directive({directive, _, [{{:., _, [{_, _, module}, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} -> {directive, meta, [{:__aliases__, [], module ++ segments}]} end)
  end

  defp expand_directive(alias), do: [alias]

  defp set_newlines({directive, meta, children}, newline) do
    updated_meta = Keyword.update(meta, :end_of_expression, [newlines: newline], &Keyword.put(&1, :newlines, newline))
    {directive, updated_meta, children}
  end
end
