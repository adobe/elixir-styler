# Styler

Styler is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling
you what's wrong, it just rewrites the code for you to fit its style rules.

## Installation

Add `:styler` as a dependency to your project's `mix.exs`:

```elixir
def deps do
  [
    {:styler, "~> 0.5", only: [:dev, :test], runtime: false},
  ]
end
```

## Usage

### As a Formatter plugin

Add `Styler` as a plugin to your `.formatter.exs` file

```elixir
[
  plugins: [Styler]
]
```

And that's it! Now when you run `mix format` you'll also get the benefits of Styler's *definitely-always-right* style fixes.

### As a Mix Task

We recommend using `Styler` as a plugin, but it comes with a task for other use cases as well.

```bash
$ mix style
```

The task can helpful for slowly converting a codebase directory-by-directory. It also allows you to use `mix archive.install`
to easily test run `Styler` on a project without modifying its dependencies:

```bash
$ mix archive.install hex styler
```

`mix style` is designed to take the same basic options as `mix format`.

See `mix help style` for more.

### Configuration

There isn't any! This is intentional.

Styler's @adobe's internal Style Guide Enforcer - allowing exceptions to the styles goes against that ethos. Happily, it's open source and thus yours to do with as you will =)

### Your first Styling

Expect the first run to take some time as `Styler` rewrites violations of styles. Afterwards, it shouldn't take much longer
than a normal mix format.

Additionally, two sad situations may happen on your first run:

* **module compilation breaks** if a reference to an alias is moved to be before the alias's declaration (part of the `StrictModuleLayout` credo rule)
    - there's nothing for it but to manually fix things, typically by writing out the entire module name where it's referenced before its alias
* **comments get put weird places**
    - sorry! only our `def`-shortening style is currently aware of comments. that means that they can get a little out of sorts when other rules move things around.
    - manually put them back where you want them, and they shouldn't be moved again
    - feel free to open or +1 an issue in the hopes that we get around to handling this

## Styles

You can find the currently-enabled styles in the `Styler` module, inside of its `@styles` module attribute. Each Style's moduledoc will tell you more about what it rewrites.

### Examples

The best place to get an idea of what sorts of changes `Styler` makes is by looking at the tests for each `Style`.

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
| `Credo.Check.Readability.OneArityFunctionInPipe` | `Styler.Style.Pipes`                 | |
| `Credo.Check.Readability.SinglePipe`                 | `Styler.Style.Pipes`                 | |
| `Credo.Check.Readability.StrictModuleLayout`         | `Styler.Style.ModuleDirectives`      | potentially destructive! (see moduledoc) |
| `Credo.Check.Readability.UnnecessaryAliasExpansion`  | `Styler.Style.ModuleDirectives`      | |
| `Credo.Check.Refactor.FilterCount`                | `Styler.Style.Pipes`                 | (in pipes only) |
| `Credo.Check.Refactor.MapInto`                | `Styler.Style.Pipes`                 | (in pipes only) |
| `Credo.Check.Refactor.MapJoin`                | `Styler.Style.Pipes`                 | (in pipes only) |
| `Credo.Check.Refactor.PipeChainStart`                | `Styler.Style.Pipes`                 | |

If you're using Credo and Styler, **we recommend disabling these rules in `.credo.exs`** to save on unnecessary checks in CI.

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
