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

  ## Credo rules

  Rewrites for the following Credo rules:

    * `Credo.Check.Consistency.MultiAliasImportRequireUse` (force expansion)
    * `Credo.Check.Readability.AliasOrder` (we sort `__MODULE__`, which credo doesn't)
    * `Credo.Check.Readability.ModuleDoc` (adds `@moduledoc false` if missing. includes `*.exs` files)
    * `Credo.Check.Readability.MultiAlias`
    * `Credo.Check.Readability.StrictModuleLayout` (see section below for details)
    * `Credo.Check.Readability.UnnecessaryAliasExpansion`

  ## Strict Layout

  **This can break your code.**

  Modules directives are sorted into the following order:

    * `@shortdoc`
    * `@moduledoc`
    * `@behaviour`
    * `use`
    * `import`
    * `alias`
    * `require`
    * everything else (unchanged)

  If any of the sorted directives had a dependency on code that is now below it, your code will fail to compile after being styled.

  For instance, the following will be broken because the module attribute definition will
  be moved below the `use` clause, meaning `@pi` is undefined when invoked.

    ```elixir
    # before `mix style`
    defmodule Approximation do
      @pi 3.14
      use Math, pi: @pi
    end

    # after `mix style`
    defmodule Approximation do
      @moduledoc false
      use Math, pi: @pi
      @pi 3.14
    end
    ```

  For now, it's up to you to come up with a fix for this issue. Sorry!
  """
  @behaviour Styler.Style

  alias Styler.Zipper

  @directives ~w(alias import require use)a
  @attr_directives ~w(moduledoc shortdoc behaviour)a

  # module names ending with these suffixes will not have a default moduledoc appended
  @dont_moduledoc ~w(Test Mixfile MixProject Controller Endpoint Repo Router Socket View HTML JSON)
  @moduledoc_false {:@, [], [{:moduledoc, [], [{:__block__, [], [false]}]}]}

  def run({{:defmodule, _, children}, _} = zipper, ctx) do
    [{:__aliases__, _, aliases}, [{{:__block__, do_meta, [:do]}, _module_body}]] = children
    # Move the zipper's focus to the module's body
    name = aliases |> List.last() |> to_string()
    add_moduledoc? = do_meta[:format] != :keyword and not String.ends_with?(name, @dont_moduledoc)
    body_zipper = zipper |> Zipper.down() |> Zipper.right() |> Zipper.down() |> Zipper.down() |> Zipper.right()

    case Zipper.node(body_zipper) do
      {:__block__, _, _} ->
        {:skip, organize_directives(body_zipper, add_moduledoc?), ctx}

      {:@, _, [{:moduledoc, _, _}]} ->
        # a module whose only child is a moduledoc. nothing to do here!
        # seems weird at first blush but lots of projects/libraries do this with their root namespace module
        {:skip, zipper, ctx}

      only_child ->
        # There's only one child, and it's not a moduledoc. Conditionally add a moduledoc, then style the only_child
        if add_moduledoc? do
          body_zipper
          |> Zipper.replace({:__block__, [], [@moduledoc_false, only_child]})
          |> Zipper.down()
          |> Zipper.right()
          |> run(ctx)
        else
          run(body_zipper, ctx)
        end
    end
  end

  def run({{d, _, _}, _} = zipper, ctx) when d in @directives do
    {:skip, zipper |> Zipper.up() |> organize_directives(), ctx}
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp organize_directives(parent, add_moduledoc? \\ false) do
    {directives, nondirectives} =
      parent
      |> Zipper.node()
      |> Zipper.children()
      |> Enum.split_with(fn
        {:@, _, [{attr, _, _}]} -> attr in @attr_directives
        {directive, _, _} -> directive in @directives
        _ -> false
      end)

    directives =
      Enum.group_by(directives, fn
        {:@, _, [{attr_name, _, _}]} -> :"@#{attr_name}"
        {directive, _, _} -> directive
      end)

    shortdocs = directives[:"@shortdoc"] || []
    moduledocs = directives[:"@moduledoc"] || if add_moduledoc?, do: [@moduledoc_false], else: []
    behaviours = expand_and_sort(directives[:"@behaviour"] || [])

    uses = (directives[:use] || []) |> Enum.flat_map(&expand_directive/1) |> reset_newlines()

    imports = expand_and_sort(directives[:import] || [])
    aliases = expand_and_sort(directives[:alias] || [])
    requires = expand_and_sort(directives[:require] || [])

    directives =
      Enum.concat([
        shortdocs,
        moduledocs,
        behaviours,
        uses,
        imports,
        aliases,
        requires
      ])

    parent = Zipper.update(parent, &Zipper.replace_children(&1, directives))

    if Enum.empty?(nondirectives) do
      parent
    else
      {last_directive, meta} = parent |> Zipper.down() |> Zipper.rightmost()
      {last_directive, %{meta | r: nondirectives}}
    end
  end

  defp expand_and_sort(directives) do
    # sorting is done with `downcase` to match Credo
    directives
    |> Enum.flat_map(&expand_directive/1)
    |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
    |> Enum.uniq_by(&elem(&1, 1))
    |> List.keysort(1)
    |> Enum.map(&elem(&1, 0))
    |> reset_newlines()
  end

  # alias Foo.{Bar, Baz}
  # =>
  # alias Foo.Bar
  # alias Foo.Baz
  defp expand_directive({directive, _, [{{:., _, [{_, _, module}, :{}]}, _, right}]}),
    do: Enum.map(right, fn {_, meta, segments} -> {directive, meta, [{:__aliases__, [], module ++ segments}]} end)

  defp expand_directive(other), do: [other]

  defp reset_newlines([]), do: []
  defp reset_newlines(directives), do: reset_newlines(directives, [])

  defp reset_newlines([directive], acc), do: Enum.reverse([set_newlines(directive, 2) | acc])
  defp reset_newlines([directive | rest], acc), do: reset_newlines(rest, [set_newlines(directive, 1) | acc])

  defp set_newlines({directive, meta, children}, newline) do
    updated_meta = Keyword.update(meta, :end_of_expression, [newlines: newline], &Keyword.put(&1, :newlines, newline))
    {directive, updated_meta, children}
  end
end
