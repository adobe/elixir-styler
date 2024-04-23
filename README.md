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
@TODO put this somewhere more reasonable
**Note** Styler's only public API is its usage as a formatter plugin. While you're welcome to play with its internals,
they can and will change without that change being reflected in Styler's semantic version.

Then add `Styler` as a plugin to your `.formatter.exs` file

```elixir
[
  plugins: [Styler]
  # optionally: include styler configuration
  # , styler: [alias_lifting_excludes: []]
]
```

And that's it! Now when you run `mix format` you'll also get the benefits of Styler's Stylish Stylings.

### Configuration

@TODO document: config for lifting, and why we won't add options other configs

Styler is @adobe's internal Style Guide Enforcer - allowing exceptions to the styles goes against that ethos. Happily, it's open source and thus yours to do with as you will =)

## Features (or as we call them, "Styles")

@TODO link examples

## Styler & Credo

@TODO link credo doc

## Your first Styling

**Speed**: Expect the first run to take some time as `Styler` rewrites violations of styles.

Once styled the first time, future styling formats shouldn't take noticeably more time.

## Styler can break your code

@TODO link troubleshooting
mention our rewrite of case true false to if and how we're OK with this being _Styler_, not _SemanticallyEquivalentRewriter_.

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
