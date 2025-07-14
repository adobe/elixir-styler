## Elixir Deprecation Rewrites

Elixir's built-in formatter now does its own rewrites via the `--migrate` flag, but doesn't quite cover every possible automated rewrite on the hard deprecations list. Styler tries to cover the rest!

Styler will rewrite deprecations so long as their alternative is available on the given elixir version. In other words, Styler doesn't care what version of Elixir you're using when it applies the ex-1.18 rewrites - all it cares about is that the alternative is valid in your version of elixir.

### Version Configuration

While most deprecation rewrites rely on the system's Elixir version, that version can be overridden for some rewrites with the `minimum_supported_elixir_version` configuration. For example, to keep Styler from using rewrites that would be incompatible with Elixir 1.15:

```elixir
# .formatter.exs
[
  plugins: [Styler],
  styler: [
    minimum_supported_elixir_version: "1.15.0"
  ]
]
```

Libraries using Styler may be running on a more modern version of Elixir while intending to support older versions. Styler can therefore break a library's minimum supported Elixir version contract when rewriting deprecated code to use more recently added standard library APIs.

For example, the `to_timeout` rewrite is only valid when running on Elixir 1.17 and greater. If a library supports older versions of Elixir it cannot use that function, and Styler automatically adding that function breaks them. This can be remedied by setting an earlier `minimum_supported_elixir_version`.

If you want to keep this configuration in sync with your project's mix.exs, consider something like the following:

```elixir
# .formatter.exs
# Parse SemVer minor elixir version from project configuration
# eg `"~> 1.15"` version requirement will yield `"1.15"`
elixir_minor_version = Regex.run(~r/([\d\.]+)/, Mix.Project.config()[:elixir])

[
  plugins: [Styler],
  styler: [
    # appending `.0` to the minor version gives us a valid SemVer version string.
    minimum_supported_elixir_version: "#{elixir_minor_version}.0"
  ]
]
```

### 1.20

[1.20 Deprecations](https://github.com/elixir-lang/elixir/blob/main/CHANGELOG.md#4-hard-deprecations)

No deprecation rewrites have been added to Styler for 1.20

### `1.19`

[1.19 Deprecations](https://github.com/elixir-lang/elixir/blob/v1.19/CHANGELOG.md#4-hard-deprecations)

### Change Struct Updates to Map Updates

1.19 deprecates struct update syntax in favor of map update syntax.

```elixir
# This
%Struct{x | y}
# Styles to this
%{x | y}
```

**WARNING** Double check your diffs to make sure your variable is pattern matching against the same struct if you want to harness 1.19's type checking features.

### 1.18

#### `List.zip/1`

```elixir
# Before
List.zip(list)
# Styled
Enum.zip(list)
```

#### `unless`

This is covered by the Elixir Formatter with the `--migrate` flag, but Styler brings the same transformation to codebases on earlier versions of Elixir, and insures future uses are automatically rewritten without relying on the flag.

Rewrite `unless x` to `if !x`

### 1.17

[1.17 Deprecations](https://hexdocs.pm/elixir/1.17.0/changelog.html#4-hard-deprecations)

- Replace `:timer.units(x)` with the new `to_timeout(unit: x)` for `hours|minutes|seconds` (relies on `minimum_supported_elixir_version`)

#### Range Matching Without Step

```elixir
# Before
first..last = range
# Styled
first..last//_ = range

# Before
def foo(x..y), do: :ok
# Styled
def foo(x..y//_), do: :ok
```

### 1.16

[1.16 Deprecations](https://hexdocs.pm/elixir/1.16.0/changelog.html#4-hard-deprecations)

#### `File.stream!/3` `:line` and `:bytes` deprecation

```elixir
# Before
File.stream!(path, [encoding: :utf8, trim_bom: true], :line)
# Styled
File.stream!(path, :line, encoding: :utf8, trim_bom: true)
```

### Explicit decreasing ranges

In all these cases, the rewrite will only be applied when literals are being passed to the function. In other words, variables will not be traced back to their assignment, and so it is still possible to receive deprecation warnings on this issue.

```elixir
# Before
Enum.slice(x, 1..-2)
# Styled
Enum.slice(x, 1..-2//1)

# Before
Date.range(~D[2000-01-01], ~D[1999-01-01])
# Styled
Date.range(~D[2000-01-01], ~D[1999-01-01], -1)
```

### 1.15

[1.15 Deprecations](https://hexdocs.pm/elixir/1.15.0/changelog.html#4-hard-deprecations)

| Before | After |
|--------|-------|
| `Logger.warn` | `Logger.warning`|
| `Path.safe_relative_to/2` | `Path.safe_relative/2`|
| `~R/my_regex/` | `~r/my_regex/`|
| `Date.range/2` with decreasing range | `Date.range/3` *|
| `IO.read/bin_read` with `:all` option | replace `:all` with `:eof`|
