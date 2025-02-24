[![Hex.pm](https://img.shields.io/hexpm/v/styler)](https://hex.pm/packages/styler)
[![Hexdocs.pm](https://img.shields.io/badge/docs-hexdocs.pm-purple)](https://hexdocs.pm/styler)
[![Github.com](https://github.com/adobe/elixir-styler/actions/workflows/ci.yml/badge.svg)](https://github.com/adobe/elixir-styler/actions)

# Styler

Styler is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling
you what's wrong, it just rewrites the code for you to fit its style rules.

You can learn more about the history, purpose and implementation of Styler from our talk: [Styler: Elixir Style-Guide Enforcer @ GigCity Elixir 2023](https://www.youtube.com/watch?v=6pF8Hl5EuD4)

## Features

Styler fixes a plethora of elixir style and optimization issues automatically as part of mix format.

[See Styler's documentation on Hex](https://hexdocs.pm/styler/styles.html) for the comprehensive list of its features.

The fastest way to see what all it can do you for you is to just try it out in your codebase... but here's a list of a few features to help you decide if you're interested in Styler:

- sorts and organizes `import`/`alias`/`require` and other [module directives](docs/module_directives.md)
- keeps lists, sigils, and even arbitrary code sorted with the `# styler:sort` [comment directive](docs/comment_directives.md)
- automatically creates aliases for repeatedly referenced modules names ([_"alias lifting"_](docs/module_directives.md#alias-lifting))
- optimizes pipe chains for [readability and performance](docs/pipes.md)
- rewrites strings as sigils when it results in fewer escapes
- auto-fixes [many credo rules](docs/credo.md), meaning you can spend less time fighting with CI

## Who is Styler for?

Styler was designed for a **large team (40+ engineers) working in a single codebase. It helps remove fiddly code review comments and removes failed linter CI slowdowns, helping teams get things done faster. Teams in similar situations might appreciate Styler.

Its automations are also extremely valuable for taming legacy elixir codebases or just refactoring in general. Some of its rewrites have inspired code actions in elixir language servers.

Conversely, Styler probably _isn't_ a good match for:

- experimental, macro-heavy codebases
- teams that don't care about code standards

## Installation

Add `:styler` as a dependency to your project's `mix.exs`:

```elixir
def deps do
  [
    {:styler, "~> 1.4", only: [:dev, :test], runtime: false},
  ]
end
```

Then add `Styler` as a plugin to your `.formatter.exs` file

```elixir
[
  plugins: [Styler]
]
```

And that's it! Now when you run `mix format` you'll also get the benefits of Styler's Stylish Stylings.

**Speed**: Expect the first run to take some time as `Styler` rewrites violations of styles and bottlenecks on disk I/O. Subsequent formats formats won't take noticeably more time.

### Configuration

Styler can be configured in your `.formatter.exs` file

```elixir
[
  plugins: [Styler],
  styler: [
    alias_lifting_exclude: [...]
  ]
]
```

Styler's only current configuration option is `:alias_lifting_exclude`, which accepts a list of atoms to _not_ lift. See the [Module Directive documentation](docs/module_directives.md#alias-lifting) for more.

#### No Credo-Style Enable/Disable

Styler [will not add configuration](https://github.com/adobe/elixir-styler/pull/127#issuecomment-1912242143) for ad-hoc enabling/disabling of rewrites. Sorry!

However, Smartrent has a fork of Styler named [Quokka](https://github.com/smartrent/quokka) that allows for finegrained control of Styler. Maybe it's what you're looking for. If not, you can always fork it or Styler as a starting point for your own tool!

Ultimately Styler is @adobe's internal tool that we're happy to share with the world. We're delighted if you like it as is, and just as excited if it's a starting point for you to make something even better for yourself.

## WARNING: Styler can change the behaviour of your program!

In some cases, this can introduce bugs. It goes without saying, but look over your changes before committing to main :)

A simple example of a way Styler changes the behaviour of code is the following rewrite:

```elixir
# Before: this case statement...
case foo do
  true -> :ok
  false -> :error
end

# After: ... is rewritten by Styler to be an if statement!.
if foo do
  :ok
else
  :error
end
```

These programs are not semantically equivalent. The former would raise if `foo` returned any value other than `true` or `false`, while the latter blissfully completes.

However, Styler is about _style_, and the `if` statement is (in our opinion) of much better style. If the exception behaviour was intentional on the code author's part, they should have written the program like this:

```elixir
case foo do
  true -> :ok
  false -> :error
  other -> raise "expected `true` or `false`, got: #{inspect other}"
end
```

Also good style! But Styler assumes that most of the time people just meant the `if` equivalent of the code, and so makes that change. If issues like this bother you, Styler probably isn't the tool you're looking for.

Other ways Styler can change your program:

- [`with` statement rewrites](https://github.com/adobe/elixir-styler/issues/186)
- [config file sorting](https://hexdocs.pm/styler/mix_configs.html#this-can-break-your-program)
- and likely other ways. stay safe out there!

## Thanks & Inspiration

### [Sourceror](https://github.com/doorgan/sourceror/)

Styler's first incarnation was as one-off scripts to rewrite an internal codebase to allow Credo rules to be turned on.

These rewrites were entirely powered by the terrific `Sourceror` library.

While `Styler` no longer relies on `Sourceror`, we're grateful for its author's help with those scripts, the inspiration
Sourceror provided in showing us what was possible, and the changes to the Elixir AST APIs that it drove.

Styler's [AST-Zipper](`m:Styler.Zipper`) implementation in this project was forked from Sourceror. Zipper has been a crucial
part of our ability to ergonomically zip around (heh) Elixir AST.

### [Credo](https://github.com/rrrene/credo/)

We never would've bothered trying to rewrite our codebase if we didn't have Credo rules we wanted to apply.

Credo's tests and implementations were referenced for implementing Styles that took the work the rest of the way.

Thanks to Credo & the Elixir community at large for coalescing around many of these Elixir style credos.
