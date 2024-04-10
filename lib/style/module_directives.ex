# Copyright 2024 Adobe. All rights reserved.
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
    * `Credo.Check.Design.AliasUsage`

  ## Breakages

  **This can break your code.**

  ### Strict Layout

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
    # before
    defmodule Approximation do
      @pi 3.14
      use Math, pi: @pi
    end

    # after
    defmodule Approximation do
      @moduledoc false
      use Math, pi: @pi
      @pi 3.14
    end
    ```

  For now, it's up to you to come up with a fix for this issue. Sorry!

  ### Strict Layout: interwoven conflicting aliases

  Ideally no one writes code like this as it's hard for our human brains to notice the context switching!
  Still, it's a possible source of breakages in Styler.


    alias Foo.Bar
    Bar.Baz.bop()

    alias Baz.Bar
    Bar.Baz.bop()

    # becomes

    alias Baz.Bar
    alias Baz.Bar.Baz
    alias Foo.Bar
    Baz.bop() # was Foo.Bar.Baz, is now Baz.Bar.Baz
    Baz.bop()
  """
  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  @directives ~w(alias import require use)a
  @callback_attrs ~w(before_compile after_compile after_verify)a
  @attr_directives ~w(moduledoc shortdoc behaviour)a ++ @callback_attrs
  @defstruct ~w(schema embedded_schema defstruct)a

  @moduledoc_false {:@, [line: nil], [{:moduledoc, [line: nil], [{:__block__, [line: nil], [false]}]}]}

  def run({{:defmodule, _, children}, _} = zipper, ctx) do
    [name, [{{:__block__, do_meta, [:do]}, _body}]] = children

    if do_meta[:format] == :keyword do
      {:skip, zipper, ctx}
    else
      moduledoc = moduledoc(name)
      # Move the zipper's focus to the module's body
      body_zipper = zipper |> Zipper.down() |> Zipper.right() |> Zipper.down() |> Zipper.down() |> Zipper.right()

      case Zipper.node(body_zipper) do
        # an empty body - replace it with a moduledoc and call it a day ¯\_(ツ)_/¯
        {:__block__, _, []} ->
          zipper = if moduledoc, do: Zipper.replace(body_zipper, moduledoc), else: body_zipper
          {:skip, zipper, ctx}

        # we want only-child literal block to be handled in the only-child catch-all. it means someone did a weird
        # (that would be a literal, so best case someone wrote a string and forgot to put `@moduledoc` before it)
        {:__block__, _, [_, _ | _]} ->
          {:skip, organize_directives(body_zipper, moduledoc), ctx}

        # a module whose only child is a moduledoc. nothing to do here!
        # seems weird at first blush but lots of projects/libraries do this with their root namespace module
        {:@, _, [{:moduledoc, _, _}]} ->
          {:skip, zipper, ctx}

        # There's only one child, and it's not a moduledoc. Conditionally add a moduledoc, then style the only_child
        only_child ->
          if moduledoc do
            zipper =
              body_zipper
              |> Zipper.replace({:__block__, [], [moduledoc, only_child]})
              |> organize_directives()

            {:skip, zipper, ctx}
          else
            run(body_zipper, ctx)
          end
      end
    end
  end

  # Style directives inside of snippets or function defs.
  def run({{directive, _, children}, _} = zipper, ctx) when directive in @directives and is_list(children) do
    # Need to be careful that we aren't getting false positives on variables or fns like `def import(foo)` or `alias = 1`
    case Style.ensure_block_parent(zipper) do
      {:ok, zipper} -> {:skip, zipper |> Zipper.up() |> organize_directives(), ctx}
      # not actually a directive! carry on.
      :error -> {:cont, zipper, ctx}
    end
  end

  # puts `@derive` before `defstruct` etc, fixing compiler warnings
  def run({{:@, _, [{:derive, _, _}]}, _} = zipper, ctx) do
    case Style.ensure_block_parent(zipper) do
      {:ok, {derive, %{l: left_siblings} = z_meta}} ->
        previous_defstruct =
          left_siblings
          |> Stream.with_index()
          |> Enum.find_value(fn
            {{struct_def, meta, _}, index} when struct_def in @defstruct -> {meta[:line], index}
            _ -> nil
          end)

        if previous_defstruct do
          {defstruct_line, defstruct_index} = previous_defstruct
          derive = Style.set_line(derive, defstruct_line - 1)
          left_siblings = List.insert_at(left_siblings, defstruct_index + 1, derive)
          {:skip, Zipper.remove({derive, %{z_meta | l: left_siblings}}), ctx}
        else
          {:cont, zipper, ctx}
        end

      :error ->
        {:cont, zipper, ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  defp moduledoc({:__aliases__, m, aliases}) do
    name = aliases |> List.last() |> to_string()
    # module names ending with these suffixes will not have a default moduledoc appended
    unless String.ends_with?(name, ~w(Test Mixfile MixProject Controller Endpoint Repo Router Socket View HTML JSON)) do
      Style.set_line(@moduledoc_false, m[:line] + 1)
    end
  end

  # a dynamic module name, like `defmodule my_variable do ... end`
  defp moduledoc(_), do: nil

  defp organize_directives(parent, moduledoc \\ nil) do
    {directives, nondirectives} =
      parent
      |> Zipper.children()
      # @TODO if i switch this to a reduce, i can keep information about whether or not i saw
      # - alias before short/module/behaviour/use/import (can get min_alias_line in that way)
      # - non-callback, non short/moduledoc/behaviour attr before any directives
      # and then use that information to conditionally dealias, conditionally de-attribute,
      # and still get it all done in a single pass. yay!
      # i believe i could simultaneously find liftable aliases?
      |> Enum.split_with(fn
        {:@, _, [{attr, _, _}]} -> attr in @attr_directives
        {directive, _, _} -> directive in @directives
        _ -> false
      end)

    directives =
      Enum.group_by(directives, fn
        # the order of callbacks relative to use can matter if the use is also doing callbacks
        # looking back, this is probably a hack to support one person's weird hackery 🤣
        # TODO drop for a 1.0 release?
        {:@, _, [{callback, _, _}]} when callback in @callback_attrs -> :use
        {:@, _, [{attr_name, _, _}]} -> :"@#{attr_name}"
        {directive, _, _} -> directive
      end)

    aliases = directives[:alias] |> List.wrap() |> expand() |> sort()
    requires = directives[:require] |> List.wrap() |> expand() |> sort()
    {aliases, requires, nondirectives} = lift_aliases(aliases, requires, nondirectives)
    min_alias_line = aliases |> Stream.map(fn {_, meta, _} -> meta[:line] end) |> Enum.min(fn -> nil end)

    directives =
      [
        directives[:"@shortdoc"] |> List.wrap() |> dealias(aliases, min_alias_line),
        directives[:"@moduledoc"] |> Kernel.||(moduledoc) |> List.wrap() |> dealias(aliases, min_alias_line),
        directives[:"@behaviour"] |> List.wrap() |> dealias(aliases, min_alias_line) |> sort(),
        directives[:use] |> List.wrap() |> expand() |> dealias(aliases, min_alias_line) |> Style.reset_newlines(),
        directives[:import] |> List.wrap() |> expand() |> dealias(aliases, min_alias_line) |> sort(),
        aliases,
        requires
      ]
      |> Stream.concat()
      |> Style.fix_line_numbers(List.first(nondirectives))

    # the # of aliases can be decreased during sorting - if there were any, we need to be sure to write the deletion
    if Enum.empty?(directives) do
      Zipper.replace_children(parent, nondirectives)
    else
      # this ensures we continue the traversal _after_ any directives
      parent
      |> Zipper.replace_children(directives)
      |> Zipper.down()
      |> Zipper.rightmost()
      |> Zipper.insert_siblings(nondirectives)
    end
  end

  defp dealias(directives, [], _), do: directives

  defp dealias(directives, aliases, min_alias_line) do
    Enum.map(directives, fn {_, meta, _} = ast ->
      line = meta[:line]

      if line < min_alias_line do
        ast
      else
        dealiases = aliases |> Enum.filter(fn {_, meta, _} -> meta[:line] < line end) |> build_dealiasing_map()

        Macro.prewalk(ast, fn
          {:__aliases__, meta, modules} -> {:__aliases__, meta, do_dealias(modules, dealiases)}
          ast -> ast
        end)
      end
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
  defp do_dealias([first | rest] = modules, dealiases) do
    if dealias = dealiases[first], do: dealias ++ rest, else: modules
  end

  defp lift_aliases(aliases, requires, nondirectives) do
    dealiasing_map = build_dealiasing_map(aliases)
    excluded = dealiasing_map |> Map.keys() |> MapSet.new() |> MapSet.union(Styler.Config.get(:lifting_excludes))
    liftable = find_liftable_aliases(requires ++ nondirectives, excluded)

    if Enum.any?(liftable) do
      # This is a silly hack that helps comments stay put.
      # the `cap_line` algo was designed to handle high-line stuff moving up into low line territory, so we set our
      # new node to have an abritrarily high line annnnd comments behave! i think.
      m = [line: 999_999]

      aliases =
        liftable
        |> Enum.map(&{:alias, m, [{:__aliases__, [{:last, m} | m], do_dealias(&1, dealiasing_map)}]})
        |> Enum.concat(aliases)
        |> sort()

      # lifting could've given us a new order
      requires = requires |> do_lift_aliases(liftable) |> sort()
      nondirectives = do_lift_aliases(nondirectives, liftable)
      {aliases, requires, nondirectives}
    else
      {aliases, requires, nondirectives}
    end
  end

  defp find_liftable_aliases(ast, excluded) do
    ast
    |> Zipper.zip()
    |> Zipper.reduce_while(%{}, fn
      # we don't want to rewrite alias name `defx Aliases ... do` of these three keywords
      {{defx, _, args}, _} = zipper, lifts when defx in ~w(defmodule defimpl defprotocol)a ->
        # don't conflict with submodules, which elixir automatically aliases
        # we could've done this earlier when building excludes from aliases, but this gets it done without two traversals.
        lifts =
          case args do
            [{:__aliases__, _, aliases} | _] when defx == :defmodule ->
              Map.put(lifts, List.last(aliases), {:collision_with_submodule, false})

            _ ->
              lifts
          end

        # move the focus to the body block, zkipping over the alias (and the `for` keyword for `defimpl`)
        {:skip, zipper |> Zipper.down() |> Zipper.rightmost() |> Zipper.down() |> Zipper.down(), lifts}

      {{:quote, _, _}, _} = zipper, lifts ->
        {:skip, zipper, lifts}

      {{:__aliases__, _, [_, _, _ | _] = aliases}, _} = zipper, lifts ->
        last = List.last(aliases)

        lifts =
          if last in excluded or not Enum.all?(aliases, &is_atom/1) do
            lifts
          else
            Map.update(lifts, last, {aliases, false}, fn
              {^aliases, _} -> {aliases, true}
              # if we have `Foo.Bar.Baz` and `Foo.Bar.Bop.Baz` both not aliased, we'll create a collision by lifting both
              # grouping by last alias lets us detect these collisions
              _ -> {:collision_with_last, false}
            end)
          end

        {:skip, zipper, lifts}

      {{:__aliases__, _, [first | _]}, _} = zipper, lifts ->
        # given:
        #   C.foo()
        #   A.B.C.foo()
        #   A.B.C.foo()
        #   C.foo()
        #
        # lifting A.B.C would create a collision with C.
        {:skip, zipper, Map.put(lifts, first, {:collision_with_first, false})}

      zipper, lifts ->
        {:cont, zipper, lifts}
    end)
    |> Enum.filter(&match?({_last, {_aliases, true}}, &1))
    |> MapSet.new(fn {_, {aliases, true}} -> aliases end)
  end

  defp do_lift_aliases(ast, to_alias) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse(fn
      {{defx, _, [{:__aliases__, _, _} | _]}, _} = zipper when defx in ~w(defmodule defimpl defprotocol)a ->
        # move the focus to the body block, zkipping over the alias (and the `for` keyword for `defimpl`)
        zipper |> Zipper.down() |> Zipper.rightmost() |> Zipper.down() |> Zipper.down() |> Zipper.right()

      {{:alias, _, [{:__aliases__, _, [_, _, _ | _] = aliases}]}, _} = zipper ->
        # the alias was aliased deeper down. we've lifted that alias to a root, so delete this alias
        if aliases in to_alias,
          do: Zipper.remove(zipper),
          else: zipper

      {{:__aliases__, meta, [_, _, _ | _] = aliases}, _} = zipper ->
        if aliases in to_alias,
          do: Zipper.replace(zipper, {:__aliases__, meta, [List.last(aliases)]}),
          else: zipper

      zipper ->
        zipper
    end)
    |> Zipper.node()
  end

  defp expand(directives), do: Enum.flat_map(directives, &expand_directive/1)

  # Deletes root level aliases ala (`alias Foo` -> ``)
  defp expand_directive({:alias, _, [{:__aliases__, _, [_]}]}), do: []

  # import Foo.{Bar, Baz}
  # =>
  # import Foo.Bar
  # import Foo.Baz
  defp expand_directive({directive, _, [{{:., _, [{:__aliases__, _, module}, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} ->
      {directive, meta, [{:__aliases__, [line: meta[:line]], module ++ segments}]}
    end)
  end

  # alias __MODULE__.{Bar, Baz}
  defp expand_directive({directive, _, [{{:., _, [{:__MODULE__, _, _} = module, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} ->
      {directive, meta, [{:__aliases__, [line: meta[:line]], [module | segments]}]}
    end)
  end

  defp expand_directive(other), do: [other]

  defp sort(directives) do
    # sorting is done with `downcase` to match Credo
    directives
    |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
    |> Enum.uniq_by(&elem(&1, 1))
    |> List.keysort(1)
    |> Enum.map(&elem(&1, 0))
    |> Style.reset_newlines()
  end

  defp build_dealiasing_map(aliases) do
    Map.new(aliases, fn
      {:alias, _, [{:__aliases__, _, aliases}]} -> {List.last(aliases), aliases}
      {:alias, _, [{:__aliases__, _, aliases}, [{_as, {:__aliases__, _, [as]}}]]} -> {as, aliases}
      # `alias __MODULE__` or other oddities
      {:alias, _, _} -> {nil, nil}
    end)
  end
end
