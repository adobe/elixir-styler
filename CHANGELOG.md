# Changelog

## main

## v0.11.9

### Improvements

* pipes: check for `Stream.foo` equivalents to `Enum.foo` in a few more cases

### Fixes

* pipes: `|> then(&(&1 op y))` rewrites with `|> Kernel.op(y)` as long as the operator is defined in `Kernel`; skips the rewrite otherwise (h/t @kerryb for the report & @saveman71 for the fix)

## v0.11.8

Two releases in one day!? @koudelka made too good a point about `Map.new` not being special...

### Improvements

* pipes: treat `MapSet.new` and `Keyword.new` the same way we do `Map.new` (h/t @koudelka)
* pipes: treat `Stream.map` the same as `Enum.map` when piped `|> Enum.into`

## v0.11.7

### Improvements

* deprecations: `~R` -> `~r`, `Date.range/2` -> `Date.range/3` with decreasing dates (h/t @milmazz)
* if: rewrite `if not x, do: y` => `unless x, do: y`
* pipes: `|> Enum.map(foo) |> Map.new()` => `|> Map.new(foo)`
* pipes: remove unnecessary `then/2` on named function captures: `|> then(&foo/1)` => `|> foo()`, `|> then(&foo(&1, ...))` => `|> foo(...)` (thanks to @tfiedlerdejanze for the idea + impl!)

## v0.11.6

### Fixes

* directives: maintain order of module compilation callbacks (`@before_compile` etc) relative to `use` statements (Closes #120, h/t @frankdugan3)

## v0.11.5

### Fixes

* fix parsing ranges with non-trivial integer bounds like `x..y` (Closes #119, h/t @maennchen)

## v0.11.4

### Improvements

Shoutout @milmazz for all the deprecation work below =)

* Deprecations: Rewrite 1.16 Deprecations (h/t @milmazz for all the work here)
  * add `//1` step to `Enum.slice/2|String.slice/2` with decreasing ranges
  * `File.stream!(file, options, line_or_bytes)` => `File.stream!(file, line_or_bytes, options)`
* Deprecations `Path.safe_relative_to/2` => `Path.safe_relative/2`

## v0.11.3

### Fixes

* directives: fix infinite loop when encountering `@spec import(...) :: ...` (Closes #115, h/t @kerryb)
* `with`: fix deletion of arrow-less `with` statements within function invocations

## v0.11.2

### Fixes

* `pipes`: fix unpiping do-blocks into variables when the parent expression is a function invocation
    like `a(if x do y end |> z(), b)` (Closes #114, h/t @wkirschbaum)

## v0.11.1

### Fixes

* `with`: fix `with` replacement when it's the only child of a `do` or `->` block (Closes #107, h/t @kerryb -- turns out those edge cases _did_ exist in the wild!)

## v0.11.0

### Improvements

#### Comments

Styler will no longer make comments jump around in any situation, and will move comments with the appropriate node in all cases but module directive rearrangement (where they'll just be left behind - sorry! we're still working on it).

* Keep comments in logical places when rewriting if/unless/cond/with (#79, #97, #101, #103)

#### With Statements

This release has a slew of improvements for `with` statements. It's not surprising that there's lots of style rules for `with` given that just about any `case`, `if`, or even `cond do` could also be expressed as a `with`. They're very powerful! And with great power...

* style trivial pattern matches ala `lhs <- rhs` to `lhs = rhs` (#86)
* style `_ <- rhs` to `rhs`
* style keyword `, do: ` to `do end` rather than wrapping multiple statements in parens
* style statements all the way to `if` statements when appropriate (#100)

#### Other

* Rewrite `{Map|Keyword}.merge(single_key: value)` to use `put/3` instead (#96)

### Fixes

* `with`: various edge cases we can only hope no one's encountered and thus never reported

## v0.10.5

After being bitten by two of them in a row, Styler's test suite now makes sure that there are no
idempotency bugs as part of its tests.

In short, we now have `assert style(x) == style(style(x))` as part of every test. Sorry for not thinking to include this before :)

### Fixes

* alias: fix single-module alias deletion newlines bug
* comments: ensure all generated nodes always include line meta (#101)

## v0.10.4

### Improvements

* alias: delete noop single-module aliases (`alias Foo`, #87, h/t @mgieger)

### Fixes

* pipes: unnest all pipe starts in one pass (`f(g(h(x))) |> j()` => `x |> h() |> g() |> f() |> j()`, #94, h/t @tomjschuster)

## v0.10.3

### Improvements

* charlists: leave charlist rewriting to elixir's formatter on elixir >= 1.15

### Fixes

* charlists: rewrite empty charlist to use sigil (`''` => `~c""`)
* pipes: don't blow up extracting fully-qualified macros (`Foo.bar do end |> foo()`, #91, h/t @NikitaNaumenko)

## v0.10.2

### Improvements

* `with`: remove identity singleton else clause (eg `else {:error, e} -> {:error, e} end`, `else error -> error end`)

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
