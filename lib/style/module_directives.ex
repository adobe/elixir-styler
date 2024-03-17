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
    * `Credo.Check.Design.AliasUsage`

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
  """
  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  @directives ~w(alias import require use)a
  @callback_attrs ~w(before_compile after_compile after_verify)a
  @attr_directives ~w(moduledoc shortdoc behaviour)a ++ @callback_attrs
  @defstruct ~w(schema embedded_schema defstruct)a

  @stdlib MapSet.new(~w(
    Access Agent Application Atom Base Behaviour Bitwise Code Date DateTime Dict Ecto Enum Exception
    File Float GenEvent GenServer HashDict HashSet Integer IO Kernel Keyword List
    Macro Map MapSet Module NaiveDateTime Node Oban OptionParser Path Port Process Protocol
    Range Record Regex Registry Set Stream String StringIO Supervisor System Task Time Tuple URI Version
  )a)

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
            body_zipper
            |> Zipper.replace({:__block__, [], [moduledoc, only_child]})
            |> Zipper.down()
            |> Zipper.right()
            |> run(ctx)
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

    shortdocs = directives[:"@shortdoc"] || []
    moduledocs = directives[:"@moduledoc"] || List.wrap(moduledoc)
    behaviours = expand_and_sort(directives[:"@behaviour"] || [])
    uses = (directives[:use] || []) |> Enum.flat_map(&expand_directive/1) |> reset_newlines()
    imports = expand_and_sort(directives[:import] || [])
    aliases = expand_and_sort(directives[:alias] || [])
    requires = expand_and_sort(directives[:require] || [])

    {aliases, requires, nondirectives} = lift_aliases(aliases, requires, nondirectives)

    directives =
      [
        shortdocs,
        moduledocs,
        behaviours,
        uses,
        imports,
        aliases,
        requires
      ]
      |> Enum.concat()
      |> fix_line_numbers(List.first(nondirectives))

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

  defp lift_aliases(aliases, requires, nondirectives) do
    excluded =
      Enum.reduce(aliases, @stdlib, fn
        {:alias, _, [{:__aliases__, _, aliases}]}, excluded -> MapSet.put(excluded, List.last(aliases))
        {:alias, _, [{:__aliases__, _, _}, [{_as, {:__aliases__, _, [as]}}]]}, excluded -> MapSet.put(excluded, as)
        # `alias __MODULE__` or other oddities
        {:alias, _, _}, excluded -> excluded
      end)

    liftable = find_liftable_aliases(requires ++ nondirectives, excluded)

    if Enum.any?(liftable) do
      # This is a silly hack that helps comments stay put.
      # the `cap_line` algo was designed to handle high-line stuff moving up into low line territory, so we set our
      # new node to have an abritrarily high line annnnd comments behave! i think.
      line = 99_999
      new_aliases = Enum.map(liftable, &{:alias, [line: line], [{:__aliases__, [last: [line: line], line: line], &1}]})
      aliases = expand_and_sort(aliases ++ new_aliases)
      requires = do_lift_aliases(requires, liftable)
      nondirectives = do_lift_aliases(nondirectives, liftable)
      {aliases, requires, nondirectives}
    else
      {aliases, requires, nondirectives}
    end
  end

  defp find_liftable_aliases(ast, excluded) do
    ast
    |> Zipper.zip()
    |> Zipper.reduce_while({%{}, excluded}, fn
      # we don't want to rewrite alias name `defx Aliases ... do` of these three keywords
      {{defx, _, args}, _} = zipper, {lifts, excluded} = acc when defx in ~w(defmodule defimpl defprotocol)a ->
        # don't conflict with submodules, which elixir automatically aliases
        # we could've done this earlier when building excludes from aliases, but this gets it done without two traversals.
        acc =
          case args do
            [{:__aliases__, _, aliases} | _] when defx == :defmodule ->
              aliased = List.last(aliases)
              {Map.delete(lifts, aliased), MapSet.put(excluded, aliased)}

            _ ->
              acc
          end

        # move the focus to the body block, zkipping over the alias (and the `for` keyword for `defimpl`)
        {:skip, zipper |> Zipper.down() |> Zipper.rightmost() |> Zipper.down() |> Zipper.down(), acc}

      {{:quote, _, _}, _} = zipper, acc ->
        {:skip, zipper, acc}

      {{:__aliases__, _, [_, _, _ | _] = aliases}, _} = zipper, {lifts, excluded} = acc ->
        if List.last(aliases) in excluded or not Enum.all?(aliases, &is_atom/1),
          do: {:skip, zipper, acc},
          else: {:skip, zipper, {Map.update(lifts, aliases, false, fn _ -> true end), excluded}}

      zipper, acc ->
        {:cont, zipper, acc}
    end)
    |> elem(0)
    # if we have `Foo.Bar.Baz` and `Foo.Bar.Bop.Baz` both not aliased, we'll create a collision by lifting both
    # grouping by last alias lets us detect these collisions
    |> Enum.group_by(fn {aliases, _} -> List.last(aliases) end)
    |> Enum.filter(fn
      {_last, [{_aliases, repeated?}]} -> repeated?
      _collision -> false
    end)
    |> MapSet.new(fn {_, [{aliases, _}]} -> aliases end)
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

  # This is the step that ensures that comments don't get wrecked as part of us moving AST nodes willy-nilly.
  #
  # For example, given document
  #
  # 1: defmodule ...
  # 2: alias B
  # 3: # hi
  # 4: # this is foo
  # 5: def foo ...
  # 6: alias A
  #
  # Moving the ast node for alias A would put line 6 before line 2 in the AST.
  # Elixir's document algebra would then encounter "line 6" and immediately dump all comments with line < 6,
  # meaning after running through the formatter we'd end up with
  #
  # 1: defmodule
  # 2: # hi
  # 3: # this is foo
  # 4: alias A
  # 5: alias B
  # 6:
  # 7: def foo ...
  #
  # This fixes that error by ensuring the following property:
  # A given node of AST cannot have a line number greater than the next AST node.
  # Et voila! Comments behave much better.
  defp fix_line_numbers(directives, acc \\ [], first_non_directive)

  defp fix_line_numbers([this, next | rest], acc, first_non_directive) do
    this = cap_line(this, next)
    fix_line_numbers([next | rest], [this | acc], first_non_directive)
  end

  defp fix_line_numbers([last], acc, first_non_directive) do
    last = if first_non_directive, do: cap_line(last, first_non_directive), else: last
    Enum.reverse([last | acc])
  end

  defp fix_line_numbers([], [], _), do: []

  defp cap_line({_, this_meta, _} = this, {_, next_meta, _}) do
    this_line = this_meta[:line]
    next_line = next_meta[:line]

    if this_line > next_line do
      # Subtracting 2 helps the behaviour with one-liner comments preceding the next node. It's a bit of a hack.
      # TODO: look into the comments list and
      # 1. move comment blocks preceding `this` up with it
      # 2. find the earliest comment before `next` and set `new_line` to that value - 1
      Style.set_line(this, next_line - 2, delete_newlines: false)
    else
      this
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

  defp reset_newlines([]), do: []
  defp reset_newlines(directives), do: reset_newlines(directives, [])

  defp reset_newlines([directive], acc), do: Enum.reverse([set_newlines(directive, 2) | acc])
  defp reset_newlines([directive | rest], acc), do: reset_newlines(rest, [set_newlines(directive, 1) | acc])

  defp set_newlines({directive, meta, children}, newline) do
    updated_meta = Keyword.update(meta, :end_of_expression, [newlines: newline], &Keyword.put(&1, :newlines, newline))
    {directive, updated_meta, children}
  end
end
