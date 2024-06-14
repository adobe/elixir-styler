## Adds Moduledoc

Adds `@moduledoc false` to modules without a moduledoc unless the module's name ends with one of the following:

* `Test`
* `Mixfile`
* `MixProject`
* `Controller`
* `Endpoint`
* `Repo`
* `Router`
* `Socket`
* `View`
* `HTML`
* `JSON`

## Directive Expansion

Expands `Module.{SubmoduleA, SubmoduleB}` to their explicit forms for ease of searching.

```elixir
# Before
import Foo.{Bar, Baz, Bop}
alias Foo.{Bar, Baz.A, Bop}

# After
import Foo.Bar
import Foo.Baz
import Foo.Bop

alias Foo.Bar
alias Foo.Baz.A
alias Foo.Bop
```

## Directive Organization

Modules directives are sorted into the following order:

* `@shortdoc`
* `@moduledoc` (adds `@moduledoc false`)
* `@behaviour`
* `use`
* `import` (sorted alphabetically)
* `alias` (sorted alphabetically)
* `require` (sorted alphabetically)
* everything else (order unchanged)

### Before

```elixir
defmodule Foo do
  @behaviour Lawful
  alias A.A
  require A

  use B

  def c(x), do: y

  import C
  @behaviour Chaotic
  @doc "d doc"
  def d do
    alias X.X
    alias H.H

    alias Z.Z
    import Ecto.Query
    X.foo()
  end
  @shortdoc "it's pretty short"
  import A
  alias C.C
  alias D.D

  require C
  require B

  use A

  alias C.C
  alias A.A

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)
end
```

### After

```elixir
defmodule Foo do
  @shortdoc "it's pretty short"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)
  @behaviour Chaotic
  @behaviour Lawful

  use B
  use A.A

  import A.A
  import C

  alias A.A
  alias C.C
  alias D.D

  require A
  require B
  require C

  def c(x), do: y

  @doc "d doc"
  def d do
    import Ecto.Query

    alias H.H
    alias X.X
    alias Z.Z

    X.foo()
  end
end
```

If any line previously relied on an alias, the alias is fully expanded when it is moved above the alias:

```elixir
# Given
alias Foo.Bar
import Bar
# Styled
import Foo.Bar

alias Foo.Bar
```

## Alias Lifting

When a module with three parts is referenced two or more times, styler creates a new alias for that module and uses it.

```elixir
# Given
require A.B.C

A.B.C.foo()
A.B.C.bar()

# Styled
alias A.B.C

require C

C.foo()
C.bar()
```

### Collisions

Styler won't lift aliases that will collide with existing aliases, and likewise won't lift any module whose name would collide with a standard library name.

You can specify additional modules to exclude from lifting via the `:alias_lifting_exclude` configuration option. For the example above, the following configuration would keep Styler from creating the `alias A.B.C` node:

```elixir
# .formatter.exs
[
  plugins: [Styler],
  styler: [alias_lifting_exclude: [:C]],
]
```
