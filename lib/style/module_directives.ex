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
  """
  @behaviour Styler.Style

  alias Styler.AliasEnv
  alias Styler.Style
  alias Styler.Zipper

  @directives ~w(alias import require use)a
  @attr_directives ~w(moduledoc shortdoc behaviour)a
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
    if !String.ends_with?(name, ~w(Test Mixfile MixProject Controller Endpoint Repo Router Socket View HTML JSON)) do
      Style.set_line(@moduledoc_false, m[:line] + 1)
    end
  end

  # a dynamic module name, like `defmodule my_variable do ... end`
  defp moduledoc(_), do: nil

  @acc %{
    shortdoc: [],
    moduledoc: [],
    behaviour: [],
    use: [],
    import: [],
    alias: [],
    require: [],
    nondirectives: [],
    dealiases: %{},
    attrs: MapSet.new(),
    attr_lifts: []
  }

  defp lift_module_attrs({node, _, _} = ast, %{attrs: attrs} = acc) do
    if Enum.empty?(attrs) do
      {ast, acc}
    else
      use? = node == :use

      Macro.prewalk(ast, acc, fn
        {:@, m, [{attr, _, _} = var]} = ast, acc ->
          if attr in attrs do
            replacement =
              if use?,
                do: {:unquote, [closing: [line: m[:line]], line: m[:line]], [var]},
                else: var

            {replacement, %{acc | attr_lifts: [attr | acc.attr_lifts]}}
          else
            {ast, acc}
          end

        ast, acc ->
          {ast, acc}
      end)
    end
  end

  defp organize_directives(parent, moduledoc \\ nil) do
    acc =
      parent
      |> Zipper.children()
      |> Enum.reduce(@acc, fn
        {:@, _, [{attr_directive, _, _}]} = ast, acc when attr_directive in @attr_directives ->
          # attr_directives are moved above aliases, so we need to dealias them
          {ast, acc} = acc.dealiases |> AliasEnv.expand(ast) |> lift_module_attrs(acc)
          %{acc | attr_directive => [ast | acc[attr_directive]]}

        {:@, _, [{attr, _, _}]} = ast, acc ->
          %{acc | nondirectives: [ast | acc.nondirectives], attrs: MapSet.put(acc.attrs, attr)}

        {directive, _, _} = ast, acc when directive in @directives ->
          {ast, acc} = lift_module_attrs(ast, acc)
          ast = expand(ast)
          # import and used get hoisted above aliases, so need to dealias
          ast = if directive in ~w(import use)a, do: AliasEnv.expand(acc.dealiases, ast), else: ast
          dealiases = if directive == :alias, do: AliasEnv.define(acc.dealiases, ast), else: acc.dealiases

          # the reverse accounts for `expand` putting things in reading order, whereas we're accumulating in reverse
          %{acc | directive => Enum.reverse(ast, acc[directive]), dealiases: dealiases}

        ast, acc ->
          %{acc | nondirectives: [ast | acc.nondirectives]}
      end)
      # Reversing once we're done accumulating since `reduce`ing into list accs means you're reversed!
      |> Map.new(fn
        {:moduledoc, []} -> {:moduledoc, List.wrap(moduledoc)}
        {:use, uses} -> {:use, uses |> Enum.reverse() |> Style.reset_newlines()}
        {directive, to_sort} when directive in ~w(behaviour import alias require)a -> {directive, sort(to_sort)}
        {:dealiases, d} -> {:dealiases, d}
        {k, v} -> {k, Enum.reverse(v)}
      end)
      |> lift_aliases()

    # Not happy with it, but this does the work to move module attribute assignments above the module or quote or whatever
    # Given that it'll only be run once and not again, i'm okay with it being inefficient
    {acc, parent} =
      if Enum.any?(acc.attr_lifts) do
        lifts = acc.attr_lifts

        nondirectives =
          Enum.map(acc.nondirectives, fn
            {:@, m, [{attr, am, _}]} = ast -> if attr in lifts, do: {:@, m, [{attr, am, [{attr, am, nil}]}]}, else: ast
            ast -> ast
          end)

        assignments =
          Enum.flat_map(acc.nondirectives, fn
            {:@, m, [{attr, am, [val]}]} -> if attr in lifts, do: [{:=, m, [{attr, am, nil}, val]}], else: []
            _ -> []
          end)

        {past, _} = parent

        parent =
          parent
          |> Zipper.up()
          |> Style.find_nearest_block()
          |> Zipper.prepend_siblings(assignments)
          |> Zipper.find(&(&1 == past))

        {%{acc | nondirectives: nondirectives}, parent}
      else
        {acc, parent}
      end

    nondirectives = acc.nondirectives

    directives =
      [
        acc.shortdoc,
        acc.moduledoc,
        acc.behaviour,
        acc.use,
        acc.import,
        acc.alias,
        acc.require
      ]
      |> Stream.concat()
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

  defp lift_aliases(%{alias: aliases, require: requires, nondirectives: nondirectives} = acc) do
    # we can't use the dealias map built into state as that's what things look like before sorting
    # now that we've sorted, it could be different!
    dealiases = AliasEnv.define(aliases)
    excluded = dealiases |> Map.keys() |> Enum.into(Styler.Config.get(:lifting_excludes))
    liftable = find_liftable_aliases(requires ++ nondirectives, excluded)

    if Enum.any?(liftable) do
      # This is a silly hack that helps comments stay put.
      # The `cap_line` algo was designed to handle high-line stuff moving up into low line territory, so we set our
      # new node to have an arbitrarily high line annnnd comments behave! i think.
      m = [line: 999_999]

      aliases =
        liftable
        |> Enum.map(&AliasEnv.expand(dealiases, {:alias, m, [{:__aliases__, [{:last, m} | m], &1}]}))
        |> Enum.concat(aliases)
        |> sort()

      # lifting could've given us a new order
      requires = requires |> do_lift_aliases(liftable) |> sort()
      nondirectives = do_lift_aliases(nondirectives, liftable)
      %{acc | alias: aliases, require: requires, nondirectives: nondirectives}
    else
      acc
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
              Map.put(lifts, List.last(aliases), :collision_with_submodule)

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
              _ -> :collision_with_last
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
        {:skip, zipper, Map.put(lifts, first, :collision_with_first)}

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

  # Deletes root level aliases ala (`alias Foo` -> ``)
  defp expand({:alias, _, [{:__aliases__, _, [_]}]}), do: []

  # import Foo.{Bar, Baz}
  # =>
  # import Foo.Bar
  # import Foo.Baz
  defp expand({directive, _, [{{:., _, [{:__aliases__, _, module}, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} ->
      {directive, meta, [{:__aliases__, [line: meta[:line]], module ++ segments}]}
    end)
  end

  # alias __MODULE__.{Bar, Baz}
  defp expand({directive, _, [{{:., _, [{:__MODULE__, _, _} = module, :{}]}, _, right}]}) do
    Enum.map(right, fn {_, meta, segments} ->
      {directive, meta, [{:__aliases__, [line: meta[:line]], [module | segments]}]}
    end)
  end

  defp expand(other), do: [other]

  defp sort(directives) do
    # sorting is done with `downcase` to match Credo
    directives
    |> Enum.map(&{&1, &1 |> Macro.to_string() |> String.downcase()})
    |> Enum.uniq_by(&elem(&1, 1))
    |> List.keysort(1)
    |> Enum.map(&elem(&1, 0))
    |> Style.reset_newlines()
  end

  # TODO investigate removing this in favor of the Style.post_sort_cleanup(node, comments)
  # "Fixes" the line numbers of nodes who have had their orders changed via sorting or other methods.
  # This "fix" simply ensures that comments don't get wrecked as part of us moving AST nodes willy-nilly.
  #
  # The fix is rather naive, and simply enforces the following property on the code:
  # A given node must have a line number less than the following node.
  # Et voila! Comments behave much better.
  #
  # ## In Detail
  #
  # For example, given document
  #
  #   1: defmodule ...
  #   2: alias B
  #   3: # this is foo
  #   4: def foo ...
  #   5: alias A
  #
  # Sorting aliases the ast node for  would put `alias A` (line 5) before `alias B` (line 2).
  #
  #   1: defmodule ...
  #   5: alias A
  #   2: alias B
  #   3: # this is foo
  #   4: def foo ...
  #
  # Elixir's document algebra would then encounter `line: 5` and immediately dump all comments with `line <= 5`,
  # meaning after running through the formatter we'd end up with
  #
  #   1: defmodule
  #   2: # hi
  #   3: # this is foo
  #   4: alias A
  #   5: alias B
  #   6:
  #   7: def foo ...
  #
  # This function fixes that by seeing that `alias A` has a higher line number than its following sibling `alias B` and so
  # updates `alias A`'s line to be preceding `alias B`'s line.
  #
  # Running the results of this function through the formatter now no longer dumps the comments prematurely
  #
  #   1: defmodule ...
  #   2: alias A
  #   3: alias B
  #   4: # this is foo
  #   5: def foo ...
  defp fix_line_numbers(nodes, nil), do: fix_line_numbers(nodes, 999_999)
  defp fix_line_numbers(nodes, {_, meta, _}), do: fix_line_numbers(nodes, meta[:line])
  defp fix_line_numbers(nodes, max), do: nodes |> Enum.reverse() |> do_fix_lines(max, [])

  defp do_fix_lines([], _, acc), do: acc

  defp do_fix_lines([{_, meta, _} = node | nodes], max, acc) do
    line = meta[:line]

    # the -2 is just an ugly hack to leave room for one-liner comments and not hijack them.
    if line > max,
      do: do_fix_lines(nodes, max, [Style.shift_line(node, max - line - 2) | acc]),
      else: do_fix_lines(nodes, line, [node | acc])
  end
end
