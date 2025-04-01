# Changelog

**Note** Styler's only public API is its usage as a formatter plugin. While you're welcome to play with its internals,
they can and will change without that change being reflected in Styler's semantic version.

## main

### Improvements

- `if`: drop empty `do` bodies like `if a, do: nil, else: b` => `if !a, do: b` (#227)

## 1.4.1

### Improvements

- `to_timeout/1` rewrites to use the next largest unit in some simple instances

    ```elixir
    # before
    to_timeout(second: 60 * m)
    to_timeout(day: 7)
    # after
    to_timeout(minute: m)
    to_timeout(week: 1)
    ```

### Fixes

- fixed styler raising when encountering invalid function definition ast

## 1.4

- A very nice change in alias lifting means Styler will make sure that your code is _using_ the aliases that it's specified.
- Shoutout to the smartrent folks for finding pipifying recursion issues
- Elixir 1.17 improvements and fixes
- Elixir 1.19-dev: delete struct updates

Read on for details.

### Improvements

#### Alias Lifting

This release taught Styler to try just that little bit harder when doing alias lifting.

- general improvements around conflict detection, lifting in more correct places and fewer incorrect places (#193, h/t @jsw800)
- use knowledge of existing aliases to shorten invocations (#201, h/t me)

    example:
        alias A.B.C

        A.B.C.foo()
        A.B.C.bar()
        A.B.C.baz()

    becomes:
        alias A.B.C

        C.foo()
        C.bar()
        C.baz()

#### Struct Updates => Map Updates

1.19 deprecates struct update syntax in favor of map update syntax.

```elixir
# This
%Struct{x | y}
# Styles to this
%{x | y}
```

**WARNING** Double check your diffs to make sure your variable is pattern matching against the same struct if you want to harness 1.19's type checking features. Apologies to folks who hoped Styler would do this step for you <3 (#199, h/t @SteffenDE)

#### Ex1.17+

- Replace `:timer.units(x)` with the new `to_timeout(unit: x)` for `hours|minutes|seconds` (This style is only applied if you're on 1.17+)

### Fixes

- `pipes`: handle pipifying when the first arg is itself a pipe: `c(a |> b, d)` => `a |> b() |> c(d)` (#214, h/t @kybishop)
- `pipes`: handle pipifying nested functions `d(c(a |> b))` => `a |> b |> c() |> d` (#216, h/t @emkguts)
- `with`: fix a stabby `with` `, else: (_ -> :ok)` being rewritten to a case (#219, h/t @iamhassangm)

## 1.3.3

### Improvements

- `with do: body` and variations with no arrows in the head will be rewritten to just `body`
- `# styler:sort` will sort arbitrary ast nodes within a `do end` block:

    Given:
        # styler:sort
        my_macro "some arg" do
          another_macro :q
          another_macro :w
          another_macro :e
          another_macro :r
          another_macro :t
          another_macro :y
        end

    We get
        # styler:sort
        my_macro "some arg" do
          another_macro :e
          another_macro :q
          another_macro :r
          another_macro :t
          another_macro :w
          another_macro :y
        end

### Fixes

- fix a bug in comment-movement when multiple `# styler:sort` directives are added to a file at the same time

## 1.3.2

### Improvements

- `# styler:sort` can be used to sort values of key-value pairs. eg, sort the value of a single key in a map (Closes #208, h/t @ypconstante)

## 1.3.1

### Improvements

- `# styler:sort` now works with maps and the `defstruct` macro

### Fixes

- `# styler:sort` no longer blows up on keyword lists :X

### Fixes

## 1.3.0

### Improvements

#### `# styler:sort` Styler's first comment directive

Styler will now keep a user-designated list or wordlist (`~w` sigil) sorted as part of formatting via the use of comments. Elements of the list are sorted by their string representation.

The intention is to remove comments to humans, like `# Please keep this list sorted!`, in favor of comments to robots: `# styler:sort`. Personally speaking, Styler is much better at alphabetical-order than I ever will be.

To use the new directive, put it on the line before a list or wordlist.

This example:

```elixir
# styler:sort
[:c, :a, :b]

# styler:sort
~w(a list of words)

# styler:sort
@country_codes ~w(
  en_US
  po_PO
  fr_CA
  ja_JP
)

# styler:sort
a_var =
  [
    Modules,
    In,
    A,
    List
  ]
```

Would yield:

```elixir
# styler:sort
[:a, :b, :c]

# styler:sort
~w(a list of words)

# styler:sort
@country_codes ~w(
  en_US
  fr_CA
  ja_JP
  po_PO
)

# styler:sort
a_var =
  [
    A,
    In,
    List,
    Modules
  ]
```

## 1.2.1

### Fixes

* `|>` don't pipify when the call is itself in a pipe (aka don't touch `a |> b(c |> d() |>e()) |> f()`) (Closes #204, h/t @paulswartz)

## 1.2.0

### Improvements

* `pipes`: pipe-ifies when first arg to a function is a pipe. reach out if this happens in unstylish places in your code (Closes #133)
* `pipes`: unpiping assignments will make the assignment one-line when possible (Closes #181)
* `deprecations`: 1.18 deprecations
    * `List.zip` => `Enum.zip`
    * `first..last = range` => `first..last//_ = range`

### Fixes

* `pipes`: optimizations are less likely to move comments (Closes #176)

## 1.1.2

### Improvements

* Config Sorting: improve comment handling when only sorting a few nodes (Closes #187)

## 1.1.1

### Improvements

* `unless`: rewrite `unless a |> b |> c` as `unless !(a |> b() |> c())` rather than `unless a |> b() |> c() |> Kernel.!()` (h/t @gregmefford)

## 1.1.0

### Improvements

The big change here is the rewrite/removal of `unless` due to [unless "eventually" being deprecated](https://github.com/elixir-lang/elixir/pull/13769#issuecomment-2334878315). Thanks to @janpieper and @ypconstante for bringing this up in #190.

* `unless`: rewrite all `unless` to `if` (#190)
* `pipes`: optimize `|> Stream.{each|map}(fun) |> Stream.run()` to `|> Enum.each(fun)`

### Fixes

* `pipes`: optimizations reducing 2 pipes to 1 no longer squeeze all pipes onto one line (#180)
* `if`: fix infinite loop rewriting negated if with empty do body `if x != y, do: (), else: :ok` (#196, h/t @itamm15)

## 1.0.0

Styler's two biggest outstanding bugs have been fixed, both related to compilation breaking during module directive organization. One was references to aliases being moved above where the aliases were declared, and the other was similarly module directives being moved after their uses in module directives.

In both cases, Styler is now smart enough to auto-apply the fixes we recommended in the old Readme.

Other than that, a slew of powerful new features have been added, the neatest one (in the author's opinion anyways) being Alias Lifting.

Thanks to everyone who reported bugs that contributed to all the fixes released in 1.0.0 as well.

### Improvements

#### Alias Lifting

Along the lines of `Credo.Check.Design.AliasUsage`, Styler now "lifts" deeply nested aliases (depth >= 3, ala `A.B.C....`) that are used more than once.

Put plainly, this code:

```elixir
defmodule A do
  def lift_me() do
    A.B.C.foo()
    A.B.C.baz()
  end
end
```

will become

```elixir
defmodule A do
  @moduledoc false
  alias A.B.C

  def lift_me do
    C.foo()
    C.baz()
  end
end
```

To exclude modules ending in `.Foo` from being lifted, add `styler: [alias_lifting_exclude: [Foo]]` to your `.formatter.exs`

#### Module Attribute Lifting

A long outstanding breakage of a first pass with Styler was breaking directives that relied on module attributes which Styler moved _after_ their uses. Styler now detects these potential breakages and automatically applies our suggested fix, which is creating a variable before the module. This usually happened when folks were using a library that autogenerated their moduledocs for them.

In code, this module:

```elixir
defmodule MyGreatLibrary do
  @library_options [...]
  @moduledoc make_pretty_docs(@library_options)
  use OptionsMagic, my_opts: @library_options

  ...
end
```

Will now be styled like so:

```elixir
library_options = [...]

defmodule MyGreatLibrary do
  @moduledoc make_pretty_docs(library_options)
  use OptionsMagic, my_opts: unquote(library_options)

  @library_options library_options

  ...
end
```

#### Mix Config File Organization

Styler now organizes `Mix.Config.config/2,3` stanzas according to erlang term sorting. This helps manage large configuration files, removing the "where should I put this" burden from developers AND helping find duplicated configuration stanzas.

See the moduledoc for `Styler.Style.Configs` for more.

#### Pipe Optimizations

* `Enum.into(x, [])` => `Enum.to_list(x)`
* `Enum.into(x, [], mapper)` => `Enum.map(x, mapper)`
* `a |> Enum.map(m) |> Enum.join()` to `map_join(a, m)`. we already did this for `join/2`, but missed the case for `join/1`
* `lhs |> Enum.reverse() |> Kernel.++(enum)` => `lhs |> Enum.reverse(enum)`

#### `with` styles

* remove `with` structure with no left arrows in its head to be normal code (#174)
* `with true <- x(), do: y` => `if x(), do: y` (#173)

#### Everything Else

* `if`/`unless`: invert if and unless with `!=` or `!==`, like we do for `!` and `not` #132
* `@derive`: move `@derive` before `defstruct|schema|embedded_schema` declarations (fixes compiler warning!) #134
* strings: rewrite double-quoted strings to use `~s` when there's 4+ escaped double-quotes
  (`"\"\"\"\""` -> `~s("""")`) (`Credo.Check.Readability.StringSigils`) #146
* `Map.drop(foo, [single_key])` => `Map.delete(foo, single_key)` #161 (also in pipes)
* `Keyword.drop(foo, [single_key])` => `Keyword.delete(foo, single_key)` #161 (also in pipes)

### Fixes

* don't blow up on `def function_head_with_no_body_nor_parens` (#185, h/t @ypconstante)
* fix `with` arrow replacement + redundant body removal creating invalid statements (#184, h/t @JesseHerrick)
* allow Kernel unary `!` and `not` as valid pipe starts (#183, h/t @nherzing)
* fix `Map.drop(x, [a | b])` registering as a chance to refactor to `Map.delete`
* `alias`: expands aliases when moving an alias after another directive that relied on it (#137)
* module directives: various fixes for unreported obscure crashes
* pipes: fix a comment-shifting scenario when unpiping
* `Timex.now/1` will no longer be rewritten to `DateTime.now!/1` due to Timex accepting a wider domain of "timezones" than the stdlib (#145, h/t @ivymarkwell)
* `with`: skip nodes which (unexpectedly) do not contain a `do` body (#158, h/t @DavidB59)
* `then(&fun/1)`: fix false positives on arithmetic `&1 + x / 1` (#164, h/t @aenglisc)

### Breaking Changes

* drop support for elixir `1.14`
* ModuleDirectives: group callback attributes (`before_compile after_compile after_verify`) with nondirectives (previously, were grouped with `use`, their relative order maintained). to keep the desired behaviour, you can make new `use` macros that wrap these callbacks. Apologies if this makes using Styler untenable for your codebase, but it's probably not a good tool for macro-heavy libraries.
* sorting configs for the first time can change your configuration; see [Mix Configs docs](docs/mix_configs.md) for more
