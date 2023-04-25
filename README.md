# Styler

Styler is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling
you what's wrong, it just rewrites the code for you to fit its style rules.

## Installation

1. Add `:styler` as a dependency to your project's `mix.exs`:

```elixir
def deps do
  [
    {:styler, "~> 0.5", only: [:dev, :test], runtime: false},
  ]
end
```

2. Add `Styler` as a plugin to your `.formatter.exs` file

```elixir
[
  plugins: [Styler],
  line_length: 100_000
]
```

## Usage

`Styler` is just a `mix format` plugin, so now your files will be styled whenever they're formatted.

```bash
$ mix format
```

Expect the initial styling of an existing codebase to take a while as it styles existing files and writes them to disk. Future runs will be just as fast as you're use to though.

## Styles

You can find the currently-enabled styles in the `Mix.Tasks.Style` module, inside of its `@styles` module attribute. Each Style's moduledoc will tell you more about what it rewrites.

### Examples

The best place to get an idea of what sorts of changes `Styler` makes is by looking at its tests!

Someday we'll announce Styler to the world, and hopefully by then we have some examples written into this here README :)

### Credo Rules Styler Replaces

| `Credo.Check`                                        | `Styler.Style`                       | Style notes              |
|------------------------------------------------------|--------------------------------------|--------------------------|
| `Credo.Check.Consistency.MultiAliasImportRequireUse` | `Styler.Style.ModuleDirectives`      | always expands `A.{B, C}` |
| `Credo.Check.Readability.AliasOrder`                 | `Styler.Style.ModuleDirectives`      | |
| `Credo.Check.Readability.BlockPipe`                  | `Styler.Style.Pipes`                 | |
| `Credo.Check.Readability.LargeNumbers`               | `Styler.Style.Simple`                | fixes bad underscores, ie: `100_00` |
| `Credo.Check.Readability.ModuleDoc`                  | `Styler.Style.ModuleDirectives`      | adds `@moduledoc false` |
| `Credo.Check.Readability.MultiAlias`                 | `Styler.Style.ModuleDirectives`      | |
| `Credo.Check.Readability.SinglePipe`                 | `Styler.Style.Pipes`                 | |
| `Credo.Check.Readability.StrictModuleLayout`         | `Styler.Style.ModuleDirectives`      | potentially destructive! (see moduledoc) |
| `Credo.Check.Readability.UnnecessaryAliasExpansion`  | `Styler.Style.ModuleDirectives`      | |
| `Credo.Check.Refactor.PipeChainStart`                | `Styler.Style.Pipes`                 | |
| `Credo.Check.Refactor.FilterCount`                | `Styler.Style.Pipes`                 | (in pipes only) |
| `Credo.Check.Refactor.MapJoin`                | `Styler.Style.Pipes`                 | (in pipes only) |
| `Credo.Check.Refactor.MapInto`                | `Styler.Style.Pipes`                 | (in pipes only) |

If you're using Credo and Styler, we recommend disabling these rules in Credo to save on unnecessary checks in CI.

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
