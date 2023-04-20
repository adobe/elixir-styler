# Changelog

## main

### Fixes

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
