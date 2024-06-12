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
# Given
import Foo.{Bar, Baz, Bop}
alias Foo.{Bar, Baz.A, Bop}

# Styled
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

```elixir
defmodule OrganizeMe do

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
