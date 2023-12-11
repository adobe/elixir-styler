# Styler

Styler is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling
you what's wrong, it just rewrites the code for you to fit its style rules.

You can learn more about the history, purpose and implementation of Styler from our talk: [Styler: Elixir Style-Guide Enforcer @ GigCity Elixir 2023](https://www.youtube.com/watch?v=6pF8Hl5EuD4)

## Installation

Add `:styler` as a dependency to your project's `mix.exs`:

```elixir
def deps do
  [
    {:styler, "~> 0.11", only: [:dev, :test], runtime: false},
  ]
end
```

Then add `Styler` as a plugin to your `.formatter.exs` file

```elixir
[
  plugins: [Styler]
]
```

And that's it! Now when you run `mix format` you'll also get the benefits of Styler's *definitely-always-right* style fixes.

### Configuration

There isn't any! This is intentional.

Styler is @adobe's internal Style Guide Enforcer - allowing exceptions to the styles goes against that ethos. Happily, it's open source and thus yours to do with as you will =)

## Features (or as we call them, "Styles")

At this point, Styler does a lot. We've catalogued a list of Credo rules that it automatically fixes, but it does some things -
like shrinking function heads down to a single line when possible - that Credo doesn't care about.

Ultimately, the best way to see what Styler does is to just try it out! What could go wrong? (You're using version control, right?)

### Credo Rules Styler Replaces

If you're using Credo and Styler, **we recommend disabling these rules in `.credo.exs`** to save on unnecessary checks in CI.

Disabling the rules means updating your `.credo.exs` depending on your configuration:

- if you're using `checks: %{enabled: [...]}`, ensure none of the checks are listed in your enabled checks
- if you're using `checks: %{disabled: [...]}`, copy/paste the snippet below into the list
- if you're using `checks: [...]`, copy/paste the snippet below into the list and ensure none of the checks appear earlier in the list

```elixir
# Styler Rewrites
#
# The following rules are automatically rewritten by Styler and so disabled here to save time
# Some of the rules have `priority: :high`, meaning Credo runs them unless we explicitly disable them
# (removing them from this file wouldn't be enough, the `false` is required)
#
# Some rules have a comment before them explaining ways Styler deviates from the Credo rule.
#
# always expands `A.{B, C}`
{Credo.Check.Consistency.MultiAliasImportRequireUse, false},
# including `case`, `fn` and `with` statements
{Credo.Check.Consistency.ParameterPatternMatching, false},
{Credo.Check.Readability.AliasOrder, false},
{Credo.Check.Readability.BlockPipe, false},
# goes further than formatter - fixes bad underscores, eg: `100_00` -> `10_000`
{Credo.Check.Readability.LargeNumbers, false},
# adds `@moduledoc false`
{Credo.Check.Readability.ModuleDoc, false},
{Credo.Check.Readability.MultiAlias, false},
{Credo.Check.Readability.OneArityFunctionInPipe, false},
# removes parens
{Credo.Check.Readability.ParenthesesOnZeroArityDefs, false},
{Credo.Check.Readability.PipeIntoAnonymousFunctions, false},
{Credo.Check.Readability.PreferImplicitTry, false},
{Credo.Check.Readability.SinglePipe, false},
# **potentially breaks compilation** - see **Troubleshooting** section below
{Credo.Check.Readability.StrictModuleLayout, false},
{Credo.Check.Readability.UnnecessaryAliasExpansion, false},
{Credo.Check.Readability.WithSingleClause, false},
{Credo.Check.Refactor.CaseTrivialMatches, false},
{Credo.Check.Refactor.CondStatements, false},
# in pipes only
{Credo.Check.Refactor.FilterCount, false},
# in pipes only
{Credo.Check.Refactor.MapInto, false},
# in pipes only
{Credo.Check.Refactor.MapJoin, false},
{Credo.Check.Refactor.NegatedConditionsInUnless, false},
{Credo.Check.Refactor.NegatedConditionsWithElse, false},
# allows ecto's `from
{Credo.Check.Refactor.PipeChainStart, false},
{Credo.Check.Refactor.RedundantWithClauseResult, false},
{Credo.Check.Refactor.UnlessWithElse, false},
{Credo.Check.Refactor.WithClauses, false},
 ```

## Your first Styling

**Speed**: Expect the first run to take some time as `Styler` rewrites violations of styles.

Once styled the first time, future styling formats shouldn't take noticeably more time.

### Troubleshooting: Compilation broke due to Module Directive rearrangement

Sometimes naively moving Module Directives around can break compilation.

Here's helpers on how to manually fix that and have a happy styling for the rest of
your codebase's life.

#### Alias dependency

If you have an alias that, for example, a `@behaviour` relies on, compilation will break after your first run.
This requires one-time manual fixing to get your repo in line with Styler's standards.

For example, if your code was this:
```elixir
defmodule MyModule do
  @moduledoc "Implements MyBehaviour!"
  alias Deeply.Nested.MyBehaviour
  @behaviour MyBehaviour
  ...
end
```

then Styler will style the file like this, which cannot compile due to `MyBehaviour` not being defined.

```elixir
defmodule MyModule do
  @moduledoc "Implements MyBehaviour!"
  @behaviour MyBehaviour  # <------ compilation error, MyBehaviour is not defined!

  alias Deeply.Nested.MyBehaviour

  ...
end
```

A simple solution is to manually expand the alias with a find-replace-all like:
`@behaviour MyBehaviour` -> `@behaviour Deeply.Nested.MyBehaviour`. It's important to specify that you only want to
find-replace with the `@behaviour` prefix or you'll unintentially expand `MyBehaviour` everywhere in the codebase.

#### Module Attribute dependency

Another common compilation break on the first run is a `@moduledoc` that depended on another module attribute which
was moved below it.

For example, given the following broken code after an initial `mix format`:

```elixir
defmodule MyGreatLibrary do
  @moduledoc make_pretty_docs(@library_options)

  @library_options [ ... ]
end
```

You can fix the code by moving the static value outside of the module into a naked variable and then reference it in the module.

Yes, this is a thing you can do in a `.ex` file =)

```elixir
library_options = [ ... ]

defmodule MyGreatLibrary do
  @moduledoc make_pretty_docs(library_options)

  @library_options library_options
end
```

## Thanks & Inspiration

### [Sourceror](https://github.com/doorgan/sourceror/)

This work was inspired by earlier large-scale rewrites of an internal codebase that used the fantastic tool `Sourceror`.

The initial implementation of Styler used Sourceror, but Sourceror's AST-embedding comment algorithm slows Styler down to
the point that it's no longer an appropriate drop-in for `mix format`.

Still, we're grateful for the inspiration Sourceror provided and the changes to the Elixir AST APIs that it drove.

The AST-Zipper implementation in this project was forked from Sourceror's implementation.

### [Credo](https://github.com/rrrene/credo/)

Similarly, this project originated from one-off scripts doing large scale rewrites of an enormous codebase as part of an
effort to enable particular Credo rules for that codebase. Credo's tests and implementations were referenced for implementing
Styles that took the work the rest of the way. Thanks to Credo & the Elixir community at large for coalescing around
many of these Elixir style credos.
