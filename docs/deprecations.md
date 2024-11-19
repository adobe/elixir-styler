## Elixir Deprecation Rewrites

| Before | After |
|--------|-------|
| `Logger.warn` | `Logger.warning`|
| `Path.safe_relative_to/2` | `Path.safe_relative/2`|
| `~R/my_regex/` | `~r/my_regex/`|
| `Enum/String.slice/2` with decreasing ranges | add explicit steps to the range * |
| `Date.range/2` with decreasing range | `Date.range/3` *|
| `IO.read/bin_read` with `:all` option | replace `:all` with `:eof`|

\* For both of the "decreasing range" changes, the rewrite can only be applied if the range is being passed as an argument to the function.

### 1.16+
File.stream! `:line` and `:bytes` deprecation

```elixir
# Before
File.stream!(path, [encoding: :utf8, trim_bom: true], :line)
# Styled
File.stream!(path, :line, encoding: :utf8, trim_bom: true)
```
