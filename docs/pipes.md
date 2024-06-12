# Pipe Chains

## Pipe Start

- raw value
- blocks are extracted to variables
- ecto's `from` is allowed

## Piped function rewrites

- add parens to function calls `|> fun |>` => `|> fun() |>`
- remove unnecessary `then/2`: `|> then(&f(&1, ...))` -> `|> f(...)`
- add `then` when defining anon funs in pipe `|> (& &1).() |>` => `|> |> then(& &1) |>`

## Piped function optimizations

Two function calls into one! Tries to fit everything on one line when shrinking.

| Before | After |
|--------|-------|
| `lhs \|> Enum.reverse() \|> Enum.concat(enum)` | `lhs \|> Enum.reverse(enum)` (also Kernel.++) |
| `lhs \|> Enum.filter(filterer) \|> Enum.count()` | `lhs \|> Enum.count(count)` |
| `lhs \|> Enum.map(mapper) \|> Enum.join(joiner)` | `lhs \|> Enum.map_join(joiner, mapper)` |
| `lhs \|> Enum.map(mapper) \|> Enum.into(empty_map)` | `lhs \|> Map.new(mapper)` |
| `lhs \|> Enum.map(mapper) \|> Enum.into(collectable)` | `lhs \|> Enum.into(collectable, mapper)` |
| `lhs \|> Enum.map(mapper) \|> Map.new()` | `lhs \|> Map.new(mapper)` mapset & keyword also |

## Unpiping Single Pipes

- notably, optimizations might turn a 2 pipe into a single pipe
- doesn't unpipe when we're starting w/ quote
- pretty straight forward i daresay
