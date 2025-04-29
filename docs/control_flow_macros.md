# Control Flow Macros (`case`, `if`, `unless`, `cond`, `with`)

Elixir's Kernel documentation refers to these structures as "macros for control-flow".
We often refer to them as "blocks" in our changelog, which is a much worse name, to be sure.

You're likely here just to see what Styler does, in which case, please [click here to skip](#if-and-unless) the following manifesto on our philosophy regarding the usage of these macros.

## Which Control Flow Macro Should I Use?

The number of "blocks" in Elixir means there are many ways to write semantically equivalent code, often leaving developers [in the dark as to which structure they should use.](https://www.reddit.com/r/elixir/comments/1ctbtcl/i_am_completely_lost_when_it_comes_to_which/)

We believe readability is enhanced by using the simplest api possible, whether we're talking about internal module function calls or standard-library macros.

### use `case`, `if`, or `cond` when...

We advocate for `case` and `if` as the first tools to be considered for any control flow as they are the two simplest blocks. If a branch _can_ be expressed with an `if` statement, it _should_ be. Otherwise, `case` is the next best choice. In situations where developers might reach for an `if/elseif/else` block in other languages, `cond do` should be used.

(`cond do` seems to see a paucity of use in the language, but many complex nested expressions or with statements can be improved by replacing them with a `cond do`).

### use `unless` when...

Never! `unless` [is being deprecated](https://github.com/elixir-lang/elixir/pull/13769#issuecomment-2334878315) and so should not be used.

Styler replaces `unless` statements with their `if` equivalent similar to using the `mix format --migrate_unless` flag.

### use `with` when...

> `with` great power comes great responsibility
>
> - Uncle Ben

As the most powerful of the Kernel control-flow expressions, `with` requires the most cognitive overhead to understand. Its power means that we can use it as a replacement for anything we might express using a `case`, `if`, or `cond` (especially with the liberal application of small private helper functions).

Unfortunately, this has lead to a proliferation of `with` in codebases where simpler expressions would have sufficed, meaning a lot of Elixir code ends up being harder for readers to understand than it needs to be.

Thus, `with` is the control-flow structure of last resort. We advocate that `with` **should only be used when more basic expressions do not suffice or become overly verbose**. As for verbosity, we subscribe to the [Chris Keathley school of thought](https://www.youtube.com/watch?v=l-8ghbdRB1w) that judicious nesting of control flow blocks within a function isn't evil and more-often-than-not is superior to spreading implementation over many small single-use functions. We'd even go so far as to suggest that cyclomatic complexity is an inexact measure of code quality, with more than a few false negatives and many false positives.

`with` is a great way to unnest multiple `case` statements when every failure branch of those statements results in the same error. This is easily and succinctly expressed with `with`'s `else` block: `else (_ -> :error)`. As Keathley says though, [Avoid Else In With Blocks](https://keathley.io/blog/good-and-bad-elixir.html#avoid-else-in-with-blocks). Having multiple else clauses "means that the error conditions matter. Which means that you don’t want `with` at all. You want `case`."

It's acceptable to use one-line `with` statements (eg `with {:ok, _} <- Repo.update(changeset), do: :ok`) to signify that other branches are uninteresting or unmodified by your code, but ultimately that can hide the possible returns of a function from the reader, making it more onerous to debug all possible branches of the code in their mental model of the function. In other words, ideally all function calls in a `with` statement head have obvious error types for the reader, leaving their omission in the code acceptable as the reader feels no need to investigate further. The example at the start of this paragraph with an `Ecto.Repo` call is a good example, as most developers in a codebase using Ecto are expected to be familiar with its basic API.

Using `case` rather than `with` for branches with unusual failure types can help document code as well as save the reader time in tracking down types. For example, replacing the following with a `with` statement that only matched against the `{:ok, _}` tuple would hide from readers that an atypically-shaped 3-tuple is returned when things go wrong.

```elixir
case some_http_call() do
  {:ok, _response} -> :ok
  {:error, http_error, response} -> {:error, http_error, response}
end
```

## `if` and `unless`

Styler removes `else: nil` clauses:

```elixir
if a, do: b, else: nil
# styled:
if a, do: b
```

It also removes `do: nil` when an `else` is present, inverting the head to maintain semantics

```elixir
if a, do: nil, else: b
# styled:
if !a, do: b
```

### Negation Inversion

Styler removes negators in the head of `if` statements by "inverting" the statement.
The following operators are considered "negators": `!`, `not`, `!=`, `!==`

Examples:

```elixir
# negated `if` statements with an `else` clause have their clauses inverted and negation removed
if !x, do: y, else: z
# Styled:
if x, do: z, else: y
```

Because elixir relies on truthy/falsey values for its `if` statements, boolean casting is unnecessary and so double negation is simply removed.

```elixir
if !!x, do: y
# styled:
if x, do: y
```

## `case`

### "Erlang heritage" `case` true/false -> `if`

Trivial true/false `case` statements are rewritten to `if` statements. While this results in a [semantically different program](https://github.com/rrrene/credo/issues/564#issue-338349517), we argue that it results in a better program for maintainability. If the developer wants their case statement to raise when receiving a non-boolean value as a feature of the program, they would better serve their callers by raising something more descriptive.

In other words, Styler leaves the code with better style, trumping obscure exception design :)

```elixir
# Styler will rewrite this even if the clause order is flipped,
# and if the `false` is replaced with a wildcard (`_`)
case foo do
  true -> :ok
  false -> :error
end

# styled:
if foo do
  :ok
else
  :error
end
```

Per the argument above, if the `if` statement is an incorrect rewrite for your program, we recommend this manual fix rewrite:

```elixir
case foo do
  true -> :ok
  false -> :error
  other -> raise "expected `true` or `false`, got: #{inspect other}"
end
```

## `cond`

Styler has only one `cond` statement rewrite: replace 2-clause statements with `if` statements.

```elixir
# Given
cond do
  a -> b
  true -> c
end
# Styled
if a do
  b
else
  c
end
```

## `with`

`with` statements are extremely expressive. Styler tries to remove any unnecessary complexity from them in the following ways.

### Remove Identity Else Clause

Like if statements with `nil` as their else clause, the identity `else` clause is the default for `with` statements and so is removed.

```elixir
# Given
with :ok <- b(), :ok <- b() do
  foo()
else
  error -> error
end
# Styled:
with :ok <- b(), :ok <- b() do
  foo()
end
```

### Remove The Statement Entirely

While you might think "surely this kind of code never appears in the wild", it absolutely does. Typically it's the result of someone refactoring a pattern away and not looking at the larger picture and realizing that the with statement now serves no purpose.

Maybe someday the compiler will warn about these use cases. Until then, Styler to the rescue.

```elixir
# Given:
with a <- b(),
     c <- d(),
     e <- f(),
     do: g,
     else: (_ -> h)
# Styled:
a = b()
c = d()
e = f()
g

# Given
with value <- arg do
  value
end
# Styled:
arg
```

### Replace `_ <- rhs` with `rhs`

This is another case of "less is more" for the reader.

```elixir
# Given
with :ok <- x,
     _ <- y(),
     {:ok, _} <- z do
  :ok
end
# Styled:
with :ok <- x,
     y(),
     {:ok, _} <- z do
  :ok
end
```

### Replace non-branching `bar <-` with `bar =`

`<-` is for branching. If the lefthand side is the trivial match (a bare variable), Styler rewrites it to use the `=` operator instead.

```elixir
# Given
with :ok <- foo(),
     bar <- baz(),
     :ok <- woo(),
     do: {:ok, bar}
# Styled
 with :ok <- foo(),
      bar = baz(),
      :ok <- woo(),
      do: {:ok, bar}
```

### Move assignments from `with` statement head

Just because any program _could_ be written entirely within the head of a `with` statement doesn't mean it should be!

Styler moves assignments that aren't trapped between `<-` outside of the head. Combined with the non-pattern-matching replacement above, we get the following:

```elixir
# Given
with foo <- bar,
     x = y,
     :ok <- baz,
     bop <- boop,
     :ok <- blop,
     foo <- bar,
     :success = hope_this_works! do
  :ok
end
# Styled:
foo = bar
x = y

with :ok <- baz,
     bop = boop,
     :ok <- blop do
  foo = bar
  :success = hope_this_works!
  :ok
end
```

### Remove redundant final clause

If the pattern of the final clause of the head is also the `with` statements `do` body, styler nixes the final match and makes the right hand side of the clause into the do body.

```elixir
# Given
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a) do
  {:ok, b}
end
# Styled:
with {:ok, a} <- foo() do
  bar(a)
end
```

### Replace with `case`

A `with` statement with a single clause in the head and an `else` body is really just a `case` statement putting on airs.

```elixir
# Given:
with :ok <- foo do
  :success
else
  :fail -> :failure
  error -> error
end
# Styled:
case foo do
  :ok -> :success
  :fail -> :failure
  error -> error
end
```

### Replace with `if`

Given Styler rewrites trivial `case` to `if`, it shouldn't be a surprise that that same rule means that `with` can be rewritten to `if` in some cases.

```elixir
# Given:
with true <- foo(), bar <- baz() do
  {:ok, bar}
else
  _ -> :error
end
# Styled:
if foo() do
  bar = baz()
  {:ok, bar}
else
  :error
end
```
