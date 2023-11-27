# Changelog

## main

### Improvements

* charlists: leave charlist rewriting to elixir's formatter on elixir >= 1.15

### Fixes

* charlists: rewrite empty charlist to use sigil (`''` => `~c""`)

## v0.10.2

### Improvements

* `with`: remove identity singleton else clause (eg `else {:error, e} -> {:error, e} end`, `else error -> error end`

## v0.10.1

### Fixes

* Fix function head shrink-failures causing comments to jump into blocks (Closes #67, h/t @APB9785)

## v0.10.0

### Improvements

* hoist all block-starts to pipes to their own variables (makes styler play better with piped macros)

### Fixes

* fix pipes starting with a macro do-block creating invalid ast (#83, h/t @mhanberg)

## v0.9.7

### Fixes

* rewrite pipes starting with `quote` blocks like we do with `case|if|cond|with` blocks (#82, h/t @SteffenDE)

## v0.9.6

### Breaking Change

* removed `mix style` task

## v0.9.5

### Fixes

* fix mistaking `Timex.now/1` in a pipe for `Timex.now/0` (#66, h/t @sabiwara)

### Removed style

* stop rewriting `Timex.today/0` given that we allow `Timex.today/1` -- too inconsistent.

## v0.9.4

### Improvements

* `if` statements: drop `else` clauses whose body is simply `nil`

## v0.9.3

### Fixes

* fix `unless a do b else c end` rewrites to `if` not flopping do/else bodies! (#77, h/t @jcowgar)
* fix pipes styling ranges with steps (`a..b//c`) incorrectly (#76, h/t @cschmatzler)

## v0.9.2

### Fixes

* fix exception styling module attributes named `@def` (we confused them with real `def`s, whoops!) (#75, h/t @randycoulman)

## v0.9.1

the boolean blocks edition!

### Improvements

* auto-fix `Credo.Check.Refactor.CondStatements` (detects any truthy atom, not just `true`)
* if/unless rewrites:
  - `Credo.Check.Refactor.NegatedConditionsWithElse`
  - `Credo.Check.Refactor.NegatedConditionsInUnless`
  - `Credo.Check.Refactor.UnlessWithElse`

## v0.9.0

the with statement edition!

### Improvements

* Added right-hand-pattern-matching rewrites to `for` and `with` left arrow expressions `<-`
  (ex: `with map = %{} <- foo()` => `with %{} = map <- foo`)
* `with` statement rewrites, solving the following credo rules
  * `Credo.Check.Readability.WithSingleClause`
  * `Credo.Check.Refactor.RedundantWithClauseResult`
  * `Credo.Check.Refactor.WithClauses`

## v0.8.5

### Fixes

* Fixed exception when encountering non-arrowed case statements ala `case foo, do: unquote(quoted)` (#69, h/t @brettinternet, nice)

## v0.8.4

### Fixes

* Timex related fixes (#66):
  * Rewrite `Timex.now/1` to `DateTime.now!/1` instead of `DateTime.utc_now/1`
  * Only rewrite `Timex.today/0`, don't change `Timex.today/1`

## v0.8.3

### Improvements

* DateTime rewrites (#62, ht @milmazz)
  * `DateTime.compare` => `DateTime.{before/after}` (elixir >= 1.15)
  * `Timex.now` => `DateTime.utc_now`
  * `Timex.today` => `Date.utc_today`

### Fixes

* Pipes: add  `!=`, `!==`, `===`, `and`, and `or` to list of valid infix operators (#64)

## v0.8.2

### Fixes

* Pipes always de-sugars keyword lists when unpiping them (#60)

## v0.8.1

### Fixes

* ModuleDirectives doesn't mistake variables for directives (#57, h/t @leandrocp)

## v0.8.0

### Improvements (Bug Fix!?)

* ModuleDirectives no longer throws comments around a file when hoisting directives up (#53)

## v0.7.14

### Improvements

* rewrite `Logger.warn/1,2` to `Logger.warning/1,2` due to Elixir 1.15 deprecation

## v0.7.13

### Fixes

* don't unpipe single-piped `unquote` expressions (h/t @elliottneilclark)

## v0.7.12

### Fixes

* fix 0-arity paren removal on metaprogramming creating uncompilable code (h/t @simonprev)

## v0.7.11

### Fixes

* fix crash from `mix style` running plugins as part of formatting (no longer runs formatter plugins)

### Improvements

* single-quote charlists are rewritten to use the `~c` sigil (`'foo'` -> `~c'foo'`) (h/t @fhunleth)
* `mix style` warns the user that Styler is primarily meant to be used as a plugin

## v0.7.10

### Fixes

* fix crash when encountering single-quote charlists (h/t @fhunleth)

### Improvements

* single-quote charlists are rewritten to use the `~c` sigil (`'foo'` -> `~c'foo'`)
* when encountering `_ = bar ->`, replace it with `bar ->`

## v0.7.9

### Fixes

* Fix a toggle state resulting from (ahem, nonsense) code like `_ = bar ->` encountering ParameterPatternMatching style

## v0.7.8

### Fixes

* Fix crash trying to remove 0-arity parens from metaprogramming ala `def unquote(foo)()`

## v0.7.7

### Improvements

* Rewrite `Enum.into/2,3` into `Map.new/1,2` when the collectable is `%{}` or `Map.new/0`

## v0.7.6

### Fixes

* Fix crash when single pipe had inner defs (h/t [@michallepicki](https://github.com/adobe/elixir-styler/issues/39))

## v0.7.5

### Fixes

* Fix bug from `ParameterPatternMatching` implementation that re-ordered pattern matching in `cond do` `->` clauses

## v0.7.4

### Features

* Implement `Credo.Check.Readability.PreferImplicitTry`
* Implement `Credo.Check.Consistency.ParameterPatternMatching` for `def|defp|fn|case`

## v0.7.3

### Features

* Remove parens from 0-arity function definitions (`Credo.Check.Readability.ParenthesesOnZeroArityDefs`)

## v0.7.2

### Features

* Rewrite `case ... true -> ...; _ -> ...` to `if` statements as well

## v0.7.1

### Features

* Rewrite `case ... true / else ->` to be `if` statements

## v0.7.0

### Features

* `Styler.Style.Simple`:
    * Optimize `Enum.reverse(foo) ++ bar` to `Enum.reverse(foo, bar)`
* `Styler.Style.Pipes`:
    * Rewrite `|> (& ...).()` to `|> then(& ...)` (`Credo.Check.Readability.PipeIntoAnonymousFunctions`)
    * Add parens to 1-arity pipe functions (`Credo.Check.Readability.OneArityFunctionInPipe`)
    * Optimize `a |> Enum.reverse() |> Enum.concat(enum)` to `Enum.reverse(a, enum)`

## v0.6.1

### Improvements

* Better error handling: `mix format` will still format files if a style fails

### Fixes

* `mix style`: only run on `.ex` and `.exs` files
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

* `ModuleDirectives`: handle dynamic module names
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
