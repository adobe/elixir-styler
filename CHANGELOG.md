# Changelog

## main

### Fixes

* `ModuleDirectives`: now expands `alias __MODULE__.{A, B}` (h/t [@adriankumpf](https://github.com/adriankumpf))

## v0.6.0

### Features

* `mix style`: brought back to life for folks who want to incrementally introduce Styler

### Fixes

* `Styler.Style.Pipes`:
   * include `x in y` and `^foo` (for ecto) as a valid pipe starts
   * work even harder to keep rewrites on one line

## v0.5.2

### Fixes

* `ModuleDirectives`: hande dynamic module names
* `Pipes`: include `Ecto.Query.from` and `Query.from` as valid pipe starts

## v0.5.1

### Improvements

* Sped up styling just a little bit

## v0.5.0

### Improvements

* `Styler` now implements `Mix.Task.Format`, meaning it is now an Elixir formatter plugin.
See the README for new installation & usage instructions

### Breaking Change! Wooo!

* the `mix style` task has been removed

## v0.4.1

### Improvements

* `Pipes` rewrites `|> Enum.into(%{}[, mapper])` and `Enum.into(Map.new()[, mapper])` to `Map.new/1,2` calls

## v0.4.0

### Improvements

* `Pipes` rewrites some two-step processes into one, fixing these credo issues in pipe chains:
    * `Credo.Check.Refactor.FilterCount`
    * `Credo.Check.Refactor.MapJoin`
    * `Credo.Check.Refactor.MapInto`

### Fixes

* `ModuleDirectives` handles even weirder places to hide your aliases (anonymous functions, in this case)
* `Pipes` tries even harder to keep single-pipe rewrites of invocations on one line

## v0.3.1

### Fixes

* `Pipes`
    * fixed omission of `==` as a valid pipe start operator (h/t @peake100 for the issue)
    * fixed rewrite of `a |> b`, where `b` was invoked without parenthesis

## v0.3.0

### Improvements

* Enabled `Defs` style and overhauled it to properly handles comments
* Optimized and tweaked `ModuleDirectives` style
    * Now culls newlines between "groups" of the same directive
    * sorts `@behaviour` directives
    * orders directives within non defmodule contexts (eg, a `def do`) if there's at least one `alias|require|use|import`

### Fixes

* `Pipes` will try to keep single-pipe rewrites on one line

## v0.2.0

### Improvements

* Added `ModuleDirectives` style
    * Note that this is potentially destructive in some rare cases. See moduledoc for more.
    * This supersedes the `Aliases` style, which has been removed.
* `mix style -` reads and writes to stdin/stdout

### Fixes

* `Pipes` style is now aware of `unless` blocks

## v0.1.1

### Improvements

* Lots of README tweaking =)
* Optimized some Zipper operations
* Added `Simple` style, replacing the following Credo rule:
    * `Credo.Check.Readability.LargeNumbers`

### Fixes

* Exceptions while parsing code now appropriately render filename rather than `nofile:xx`
* Fixed opaque `Zipper.path()` typespec implementation mismatches (thanks @sega-yarkin)
* Made `ex_doc` dev only, removing it as a dependency for users of Styler

## v0.1.0

### Improvements

* Initial release of Styler
* Added `Aliases` style, replacing the following Credo rules:
    * `Credo.Check.Readability.AliasOrder`
    * `Credo.Check.Readability.MultiAlias`
    * `Credo.Check.Readability.UnnecessaryAliasExpansion`
* Added `Pipes` style, replacing the following Credo rules:
    * `Credo.Check.Readability.BlockPipe`
    * `Credo.Check.Readability.SinglePipe`
    * `Credo.Check.Refactor.PipeChainStart`
* Added `Defs` style (currently disabled by default)
