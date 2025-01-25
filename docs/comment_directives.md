## Comment Directives

Comment Directives are a Styler feature that let you instruct Styler to do maintain additional formatting via comments.

The plural in the name is optimistic as there's currently only one, but who knows

### `# styler:sort`

Styler can keep static values sorted for your team as part of its formatting pass. To instruct it to do so, replace any `# Please keep this list sorted!` notes you wrote to your teammates with `# styler:sort`

Sorting is done via string comparison of the code.

Styler knows how to sort the following things:

- lists of elements
- arbitrary code within `do end` blocks (helpful for schema-like macros)
- `~w` sigils elements
- keyword shapes (structs, maps, and keywords)

Since you can't have comments in arbitrary places when using Elixir's formatter,
Styler will apply those sorts when they're on the righthand side fo the following operators:

- module directives (eg `@my_dir ~w(a list of things)`)
- assignments (eg `x = ~w(a list again)`)
- `defstruct`

#### Examples

**Before**

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

# styler:sort
my_macro "some arg" do
  another_macro :q
  another_macro :w
  another_macro :e
  another_macro :r
  another_macro :t
  another_macro :y
end
```

**After**

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

# styler:sort
my_macro "some arg" do
  another_macro :e
  another_macro :q
  another_macro :r
  another_macro :t
  another_macro :w
  another_macro :y
end
```
