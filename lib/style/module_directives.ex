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
  @attr_directives ~w(moduledoc shortdoc behaviour)a

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
        {:__block__, _, _} ->
          {zipper, comments} = organize_directives(body_zipper, moduledoc, ctx.comments)
          {:skip, zipper, %{ctx | comments: comments}}

        {:@, _, [{:moduledoc, _, _}]} ->
          # a module whose only child is a moduledoc. nothing to do here!
          # seems weird at first blush but lots of projects/libraries do this with their root namespace module
          {:skip, zipper, ctx}

        only_child ->
          # There's only one child, and it's not a moduledoc. Conditionally add a moduledoc, then style the only_child
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

  def run({{def, _, children}, _} = zipper, ctx) when def in ~w(def defp defmacro defmacrop)a and is_list(children) do
    # we don't want to look at import nodes like `def import(foo)`
    if def_body = zipper |> Zipper.down() |> Zipper.right(),
      do: {:cont, def_body, ctx},
      else: {:skip, zipper, ctx}
  end

  def run({{directive, _, children}, _} = zipper, ctx) when directive in @directives and is_list(children) do
    parent = zipper |> Style.ensure_block_parent() |> Zipper.up()
    {zipper, comments} = organize_directives(parent, ctx.comments)
    {:skip, zipper, %{ctx | comments: comments}}
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

  defp organize_directives(parent, moduledoc \\ nil, comments) do
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
        {:@, _, [{attr_name, _, _}]} -> :"@#{attr_name}"
        {directive, _, _} -> directive
      end)

    shortdocs = directives[:"@shortdoc"] || []
    moduledocs = directives[:"@moduledoc"] || List.wrap(moduledoc)
    behaviours = expand_and_sort(directives[:"@behaviour"] || [])

    uses = (directives[:use] || []) |> Enum.flat_map(&expand_directive/1) |> reset_newlines()
    imports = expand_and_sort(directives[:import] || [])
    requires = expand_and_sort(directives[:require] || [])
    all_aliases = directives[:alias] || []
    aliases = expand_and_sort(all_aliases)

    {directives, comments} =
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
      |> fix_line_numbers(List.first(nondirectives), comments)

    zipper =
      cond do
        # the # of aliases can be decreased during sorting - if there were any, we need to be sure to write the deletion
        Enum.empty?(directives) and Enum.empty?(all_aliases) ->
          parent

        Enum.empty?(nondirectives) ->
          Zipper.update(parent, &Zipper.replace_children(&1, directives))

        true ->
          parent
          |> Zipper.update(&Zipper.replace_children(&1, directives))
          |> Zipper.down()
          |> Zipper.rightmost()
          |> Zipper.insert_siblings(nondirectives)
      end

    {zipper, comments}
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
  defp fix_line_numbers(directives, acc \\ [], first_non_directive, comments)

  defp fix_line_numbers([this, next | rest], acc, first_non_directive, comments) do
    {this, comments} = cap_line(this, next, comments)
    fix_line_numbers([next | rest], [this | acc], first_non_directive, comments)
  end

  defp fix_line_numbers([last], acc, first_non_directive, comments) do
    {last, comments} = if first_non_directive, do: cap_line(last, first_non_directive, comments), else: {last, comments}
    {Enum.reverse([last | acc]), comments}
  end

  defp fix_line_numbers([], [], _, comments), do: {[], comments}

  defp cap_line({_, this_meta, _} = this, {_, next_meta, _}, comments) do
    this_line = this_meta[:line]
    next_line = next_meta[:line]

    if this_line > next_line do
      # it's not enought to say "give me comments from previous lines"
      # because the precious line could be
      # alias A # this is A
      # and so we'd steal the alias from A!
      # instead, we need to annotate each node with the line number of the preceding line of ast
      # not sure what the best way to do tha tis. it needs to be Zipper.prev, not left, unless I use max_line to get the max from each prev...
      # once things are annotated, we can know exactly what range to look for comments to attach to this node
      # (preceding_ast_line + 1).. this_line
      # the comments need to be popped out of place and put back into comments list as a group,
      # to make sure i don't intersperse comments
      comments = Style.move_preceding_comments(comments, this_line, next_line - 2)
      this = Style.set_line(this, next_line - 2, delete_newlines: false)
      {this, comments}
    else
      {this, comments}
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
