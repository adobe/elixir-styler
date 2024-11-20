# Simple (Single Node) Styles

Function Performance & Readability Optimizations

Optimizing for either performance or readability, probably both!
These apply to the piped versions as well

## Strings to Sigils

Rewrites strings with 4 or more escaped quotes to string sigils with an alternative delimiter.
The delimiter will be one of `" ( { | [ ' < /`, chosen by which would require the fewest escapes, and otherwise preferred in the order listed.

```elixir
# Before
"{\"errors\":[\"Not Authorized\"]}"
# Styled
~s({"errors":["Not Authorized"]})
```

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
| `Enum.into(enum, MapSet.new())` | `MapSet.new(enum)`|
| `Enum.into(enum, %{}, fn x -> {x, x} end)` | `Map.new(enum, fn x -> {x, x} end)`|
| `Enum.into(enum, [])` | `Enum.to_list(enum)` |
| `Enum.into(enum, [], mapper)` | `Enum.map(enum, mapper)`|

## Map/Keyword.merge w/ single key literal -> X.put

`Keyword.merge` and `Map.merge` called with a literal map or keyword argument with a single key are rewritten to the equivalent `put`, a cognitively simpler function.

```elixir
# Before
Keyword.merge(kw, [key: :value])
# Styled
Keyword.put(kw, :key, :value)

# Before
Map.merge(map, %{key: :value})
# Styled
Map.put(map, :key, :value)

# Before
Map.merge(map, %{key => value})
# Styled
Map.put(map, key, value)

# Before
map |> Map.merge(%{key: value}) |> foo()
# Styled
map |> Map.put(:key, value) |> foo()
```

## Map/Keyword.drop w/ single key -> X.delete

In the same vein as the `merge` style above, `[Map|Keyword].drop/2` with a single key to drop are rewritten to use `delete/2`
```elixir
# Before
Map.drop(map, [key])
# Styled
Map.delete(map, key)

# Before
Keyword.drop(kw, [key])
# Styled
Keyword.delete(kw, key)
```

## `Enum.reverse/1` and concatenation -> `Enum.reverse/2`

`Enum.reverse/2` optimizes a two-step reverse and concatenation into a single step.

```elixir
# Before
Enum.reverse(foo) ++ bar
# Styled
Enum.reverse(foo, bar)

# Before
baz |> Enum.reverse() |> Enum.concat(bop)
# Styled
Enum.reverse(baz, bop)
```

## `Timex.now/0` -> `DateTime.utc_now/0`

Timex certainly has its uses, but knowing what stdlib date/time struct is returned by `now/0` is a bit difficult!

We prefer calling the actual function rather than its rename in Timex, helping the reader by being more explicit.

This also hews to our internal styleguide's "Don't make one-line helper functions" guidance.

## `DateModule.compare/2` -> `DateModule.[before?|after?]`

Again, the goal is readability and maintainability. `before?/2` and `after?/2` were implemented long after `compare/2`,
so it's not unusual that a codebase needs a lot of refactoring to be brought up to date with these new functions.
That's where Styler comes in!

The examples below use `DateTime.compare/2`, but the same is also done for `NaiveDateTime|Time|Date.compare/2`

```elixir
# Before
DateTime.compare(start, end_date) == :gt
# Styled
DateTime.after?(start, end_date)

# Before
DateTime.compare(start, end_date) == :lt
# Styled
DateTime.before?(start, end_date)
```

## Implicit `try`

Styler will rewrite functions whose entire body is a try/do to instead use the implicit try syntax, per Credo's `Credo.Check.Readability.PreferImplicitTry`

```elixir
# before
def foo do
  try do
    throw_ball()
  catch
    :ball -> :caught
  end
end

# Styled:
def foo do
  throw_ball()
catch
  :ball -> :caught
end
```

## Remove parenthesis from 0-arity function & macro definitions

The author of the library disagrees with this style convention :) BUT, the wonderful thing about Styler is it lets you write code how _you_ want to, while normalizing it for reading for your entire team. The most important thing is not having to think about the style, and instead focus on what you're trying to achieve.

```elixir
# Before
def foo() do
defp foo() do
defmacro foo() do
defmacrop foo() do

# Styled
def foo do
defp foo do
defmacro foo do
defmacrop foo do
```

## Variable matching on the right

```elixir
# Before
case foo do
  bar = %{baz: baz? = true} -> :baz?
  opts = [[a = %{}] | _] -> a
end
# Styled:
case foo do
  %{baz: true = baz?} = bar -> :baz?
  [[%{} = a] | _] = opts -> a
end

# Before
with {:ok, result = %{}} <- foo, do: result
# Styled
with {:ok, %{} = result} <- foo, do: result

# Before
def foo(bar = %{baz: baz? = true}, opts = [[a = %{}] | _]), do: :ok
# Styled
def foo(%{baz: true = baz?} = bar, [[%{} = a] | _] = opts), do: :ok
```

## Drops superfluous `= _` in pattern matching

```elixir
# Before
def foo(_ = bar), do: bar
# Styled
def foo(bar), do: bar

# Before
case foo do
  _ = bar -> :ok
end
# Styled
case foo do
  bar -> :ok
end
```

## Shrink Function Definitions to One Line When Possible

```elixir
# Before

def save(
       # Socket comment
       %Socket{assigns: %{user: user, live_action: :new}} = initial_socket,
       # Params comment
       params
     ),
     do: :ok

# Styled

# Socket comment
# Params comment
def save(%Socket{assigns: %{user: user, live_action: :new}} = initial_socket, params), do: :ok
```
