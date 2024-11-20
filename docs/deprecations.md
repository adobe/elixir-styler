## Elixir Deprecation Rewrites

Elixir's built-in formatter now does its own rewrites via the `--migrate` flag, but doesn't quite cover every possible automated rewrite on the hard deprecations list. Styler tries to cover the rest!

Styler will rewrite deprecations so long as their alternative is available on the given elixir version. In other words, Styler doesn't care what version of Elixir you're using when it applies the ex-1.18 rewrites - all it cares about is that the alternative is valid in your version of elixir.

### elixir `main`

https://github.com/elixir-lang/elixir/blob/main/CHANGELOG.md#4-hard-deprecations

These deprecations will be released with Elixir 1.18

#### `List.zip/1`

```elixir
# Before
List.zip(list)
# Styled
Enum.zip(list)
```

#### `unless`

This is covered by the Elixir Formatter with the `--migrate` flag, but Styler brings the same transformation to codebases on earlier versions of Elixir.

Rewrite `unless x` to `if !x`

### 1.17

[1.17 Deprecations](https://hexdocs.pm/elixir/1.17.0/changelog.html#4-hard-deprecations)

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
