# Styler

Styler is an AST-rewriting tool. Think of it as a combination of `mix format` and `mix credo`, except instead of telling
you what's wrong, it just rewrites the code for you to fit our style rules. Hence, `mix style`!

Styler is configuration-free. Like `mix format`, it runs based on the `inputs` from `.formatter.exs` and has opinions rather than configuration.

## Installation

Add `:styler` as a dependency to your project's `mix.exs`:

```
def deps do
  [
    {:styler, "~> 0.1", only: [:dev, :test], runtime: false},
  ]
end
```

Styler is meant to be a 1-1 replacement for `mix format`. So at your discretion, you can alias it in place of `format`

```
def aliases do
  [
    format: "style"
  ]
end
```

## Usage

```bash
$ mix style
```

This will rewrite your code according to the Styles of `Styler` and format it.

As stated above, `Styler` takes a cue from Elixir's Formatter and offers no configuration. Instead, it harnesses the same `.formatter.exs` file as Formatter to know which files within your project it should style.

### Styler and Comments...

Styler is currently unaware of comments, so you may find that it puts them in really odd spots after a rewrite.

If you find that a comment was put somewhere weird after using Styler, you'll just have to manually put it back where you want it after.
Feel free to grumble about it in an Issue so that we can properly prioritize making this work better in the future.

## Current Styles

You can find the currently-enabled styles in the `Mix.Tasks.Style` module, inside of its `@styles` module attribute. Each Style's moduledoc will tell you more about what it rewrites.

## Credo Rules Styler Replaces

| credo rule                            | style that rewrites to suit          |
|---------------------------------------|--------------------------------------|
| `Credo.Check.Readability.AliasOrder`  | `Styler.Style.Aliases`               |
| `Credo.Check.Readability.MultiAlias`  | `Styler.Style.Aliases`               |
| `Credo.Check.Readability.UnnecessaryAliasExpansion` | `Styler.Style.Aliases` |
| `Credo.Check.Readability.SinglePipe`  | `Styler.Style.Pipes`                 |
| `Credo.Check.Refactor.PipeChainStart` | `Styler.Style.Pipes`                 |

## Writing Styles

Write a new Style by implementing the `Styler.Style` behaviour. See its moduledoc for more.

## Thanks & Inspiration

### Sourceror

This work was inspired by earlier large-scale rewrites of an internal codebase that used the fantastic tool [`Sourceror`](https://github.com/doorgan/sourceror/).

The initial implementation of Styler used Sourceror, but Sourceror's AST-embedding comment algorithm slows Styler down to
the point that it's no longer an appropriate drop-in for `mix format`.

Still, we're grateful for the inspiration Sourceror provided and the changes to the Elixir AST APIs that it drove.

The AST-Zipper implementation in this project was forked from Sourceror's implementation.

### Credo

Similarly, this project originated from one-off scripts doing large scale rewrites of an enormous codebase as part of an
effort to enable particular Credo rules for that codebase. Credo's tests and implementations were referenced for implementing
Styles that took the work the rest of the way. Thanks to Credo & the Elixir community at large for coalescing around
many of these Elixir style credos.
