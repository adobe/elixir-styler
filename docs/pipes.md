## Pipe Chains

### Pipe Start

Styler will ensure that the start of a pipechain is a 0-arity function, a raw value, or a variable.

```elixir
Enum.at(enum, 5)
|> IO.inspect()

# Styled:
enum
|> Enum.at(5)
|> IO.inspect()
```

If the start of a pipe is a block expression, styler will create a new variable to store the result of that expression and make that variable the start of the pipe.

```elixir
if a do
  b
else
  c
end
|> Enum.at(4)
|> IO.inspect()

# Styled:
if_result =
  if a do
    b
  else
    c
  end

if_result
|> Enum.at(4)
|> IO.inspect()
```

### Add parenthesis to function calls in pipes

```elixir
a |> b |> c |> d
# Styled:
a |> b() |> c() |> d()
```

### Remove Unnecessary `then/2`

When the piped argument is being passed as the first argument to the inner function, there's no need for `then/2`.

```elixir
a |> then(&f(&1, ...)) |> b()
# Styled:
a |> f(...) |> b()
```

- add parens to function calls `|> fun |>` => `|> fun() |>`

### Add `then/2` when defining and calling anonymous functions in pipes

```elixir
a |> (fn x -> x end).() |> c()
# Styled:
a |> then(fn x -> x end) |> c()
```

### Piped function optimizations

Two function calls into one! Fewer steps is always nice.

```elixir
# reverse |> concat => reverse/2
a |> Enum.reverse() |> Enum.concat(enum) |> ...
# Styled:
a |> Enum.reverse(enum) |> ...

# filter |> count => count(filter)
a |> Enum.filter(filterer) |> Enum.count() |> ...
# Styled:
a |> Enum.count(filterer) |> ...

# map |> join => map_join
a |> Enum.map(mapper) |> Enum.join(joiner) |> ...
# Styled:
a |> Enum.map_join(joiner, mapper) |> ...

# Enum.map |> X.new() => X.new(mapper)
# where X is one of: Map, MapSet, Keyword
a |> Enum.map(mapper) |> Map.new() |> ...
# Styled:
a |> Map.new(mapper) |> ...

# Enum.map |> Enum.into(empty_collectable) => X.new(mapper)
# Where empty_collectable is one of `%{}`, `Map.new()`, `Keyword.new()`, `MapSet.new()`
# Given:
a |> Enum.map(mapper) |> Enum.into(%{}) |> ...
# Styled:
a |> Map.new(mapper) |> ...

# Given:
a |> b() |> Stream.each(fun) |> Stream.run()
a |> b() |> Stream.map(fun) |> Stream.run()
# Styled:
a |> b() |> Enum.each(fun)
a |> b() |> Enum.each(fun)
```

### Unpiping Single Pipes

Styler rewrites pipechains with a single pipe to be function calls. Notably, this rule combined with the optimizations rewrites above means some chains with more than one pipe will also become function calls.

```elixir
foo = bar |> baz()
# Styled:
foo = baz(bar)

map = a |> Enum.map(mapper) |> Map.new()
# Styled:
map = Map.new(a, mapper)
```

### Pipe-ify

If the first argument to a function call is a pipe, Styler makes the function call the final pipe of the chain.

```elixir
d(a |> b |> c)
# Styled
a |> b() |> c() |> d()
```
