# Simple (Single Node) Styles

Function Performance & Readability Optimizations

Optimizing for either performance or readability, probably both!
These apply to the piped versions as well

## Strings to Sigils

Rewrites strings with 4 or more escaped quotes to string sigils with an alternative delimiter.
The delimiter will be one of `" ( { | [ ' < /`, chosen by which would require the fewest escapes, and otherwise preferred in the order listed.

* `"{\"errors\":[\"Not Authorized\"]}"` => `~s({"errors":["Not Authorized"]})`

## Large Base 10 Numbers

Style base 10 numbers with 5 or more digits to have a `_` every three digits.
Formatter already does this except it doesn't rewrite "typos" like `100_000_0`.

If you're concerned that this breaks your team's formatting for things like "cents" (like "$100" being written as `100_00`),
consider using a library made for denoting currencies rather than raw elixir integers.

| Before | After |
|--------|-------|
| `10000 ` | `10_000`|
| `1_0_0_0_0` | `10_000` (elixir's formatter leaves the former as-is)|
| `-543213 ` | `-543_213`|
| `123456789 ` | `123_456_789`|
| `55333.22 ` | `55_333.22`|
| `-123456728.0001 ` | `-123_456_728.0001`|

## `Enum.into` -> `X.new`

This rewrite is applied when the collectable is a new map, keyword list, or mapset via `Enum.into/2,3`.

This is an improvement for the reader, who gets a more natural language expression: "make a new map from enum" vs "enumerate enum and collect its elements into a new map"

Note that all of the examples below also apply to pipes (`enum |> Enum.into(...)`)

| Before | After |
|--------|-------|
| `Enum.into(enum, %{})` | `Map.new(enum)`|
| `Enum.into(enum, Map.new())` | `Map.new(enum)`|
| `Enum.into(enum, Keyword.new())` | `Keyword.new(enum)`|
| `Enum.into(enum, MapSet.new())` | `Keyword.new(enum)`|
| `Enum.into(enum, %{}, fn x -> {x, x} end)` | `Map.new(enum, fn x -> {x, x} end)`|
| `Enum.into(enum, [])` | `Enum.to_list(enum)` |
| `Enum.into(enum, [], mapper)` | `Enum.map(enum, mapper)`|

## Map/Keyword.merge w/ single key literal -> X.put

`Keyword.merge` and `Map.merge` called with a literal map or keyword argument with a single key are rewritten to the equivalent `put`, a cognitively simpler function.
| Before | After |
|--------|-------|
| `Keyword.merge(kw, [key: :value])` | `Keyword.put(kw, :key, :value)` |
| `Map.merge(map, %{key: :value})` | `Map.put(map, :key, :value)` |
| `Map.merge(map, %{key => value})` | `Map.put(map, key, value)` |
| `map |> Map.merge(%{key: value}) |> foo()` | `map |> Map.put(:key, value) |> foo()` |

## Map/Keyword.drop w/ single key -> X.delete

In the same vein as the `merge` style above, `[Map|Keyword].drop/2` with a single key to drop are rewritten to use `delete/2`
| Before | After |
|--------|-------|
| `Map.drop(map, [key])` | `Map.delete(map, key)`|
| `Keyword.drop(kw, [key])` | `Keyword.delete(kw, key)`|

## `Enum.reverse/1` and concatenation -> `Enum.reverse/2`

`Enum.reverse/2` optimizes a two-step reverse and concatenation into a single step.

| Before | After |
|--------|-------|
| `Enum.reverse(foo) ++ bar` | `Enum.reverse(foo, bar)`|
| `baz \|> Enum.reverse() \|> Enum.concat(bop)` | `Enum.reverse(baz, bop)`|

## `Timex.now/0` ->` DateTime.utc_now/0`

Timex certainly has its uses, but knowing what stdlib date/time struct is returned by `now/0` is a bit difficult!

We prefer calling the actual function rather than its rename in Timex, helping the reader by being more explicit.

This also hews to our internal styleguide's "Don't make one-line helper functions" guidance.

## `DateModule.compare/2` -> `DateModule.[before?|after?]`

Again, the goal is readability and maintainability. `before?/2` and `after?/2` were implemented long after `compare/2`,
so it's not unusual that a codebase needs a lot of refactoring to be brought up to date with these new functions.
That's where Styler comes in!

The examples below use `DateTime.compare/2`, but the same is also done for `NaiveDateTime|Time|Date.compare/2`

| Before | After |
|--------|-------|
| `DateTime.compare(start, end_date) == :gt` | `DateTime.after?(start, end_date)` |
| `DateTime.compare(start, end_date) == :lt` | `DateTime.before?(start, end_date)` |

## Implicit Try

Styler will rewrite functions whose entire body is a try/do to instead use the implicit try syntax, per Credo's `Credo.Check.Readability.PreferImplicitTry`

The following example illustrates the most complex case, but Styler happily handles just basic try do/rescue bodies just as easily.

### Before

```elixir
def foo() do
  try do
    uh_oh()
  rescue
    exception -> {:error, exception}
  catch
    :a_throw -> {:error, :threw!}
  else
    try_has_an_else_clause? -> {:did_you_know, try_has_an_else_clause?}
  after
    :done
  end
end
```

### After

```elixir
def foo() do
  uh_oh()
rescue
  exception -> {:error, exception}
catch
  :a_throw -> {:error, :threw!}
else
  try_has_an_else_clause? -> {:did_you_know, try_has_an_else_clause?}
after
  :done
end
```

## Remove parenthesis from 0-arity function & macro definitions

The author of the library disagrees with this style convention :) BUT, the wonderful thing about Styler is it lets you write code how _you_ want to, while normalizing it for reading for your entire team. The most important thing is not having to think about the style, and instead focus on what you're trying to achieve.

| Before | After |
|--------|-------|
| `def foo()` | `def foo`|
| `defp foo()` | `defp foo`|
| `defmacro foo()` | `defmacro foo`|
| `defmacrop foo()` | `defmacrop foo`|

## Elixir Deprecation Rewrites

### 1.15+

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
| Before | After |
|--------|-------|
|`File.stream!(file, options, line_or_bytes)` | `File.stream!(file, line_or_bytes, options)`|


## Code Readability

- put matches on right
- `Credo.Check.Readability.PreferImplicitTry`

## Function Definitions

- Shrink multi-line function defs
- Put assignments on the right

## `cond`
- Credo.Check.Refactor.CondStatements

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
| `lhs |> Enum.reverse() |> Enum.concat(enum)` | `lhs |> Enum.reverse(enum)` (also Kernel.++) |
| `lhs |> Enum.filter(filterer) |> Enum.count()` | `lhs |> Enum.count(count)` |
| `lhs |> Enum.map(mapper) |> Enum.join(joiner)` | `lhs |> Enum.map_join(joiner, mapper)` |
| `lhs |> Enum.map(mapper) |> Enum.into(empty_map)` | `lhs |> Map.new(mapper)` |
| `lhs |> Enum.map(mapper) |> Enum.into(collectable)` | `lhs |> Enum.into(collectable, mapper)` |
| `lhs |> Enum.map(mapper) |> Map.new()` | `lhs |> Map.new(mapper)` mapset & keyword also |

## Unpiping Single Pipes

- notably, optimizations might turn a 2 pipe into a single pipe
- doesn't unpipe when we're starting w/ quote
- pretty straight forward i daresay
