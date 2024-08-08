# Mix Configs

Mix Config files have their config stanzas sorted. Similar to the sorting of aliases, this delivers consistency to an otherwise arbitrary world, and can even help catch bugs like configuring the same key multiple times.

A file is considered a config file if

1. its path matches `~r|config/.*\.exs|` `~r|rel/overlays/.*\.exs|`
2. the file has `import Config`

Once a file is detected as a mix config, its `config/2,3` stanzas are grouped and ordered like so:

- group config stanzas separated by assignments (`x = y`) together
- sort each group according to erlang term sorting
- move all existing assignments between the config stanzas to above the stanzas (without changing their ordering)

## THIS CAN BREAK YOUR PROGRAM

It's important to double check your configuration after running Styler on it for the first time.

**First Use Advice**: To limit the size of changes Styler submits to a codebase, we recommend formatting only a few (or a single) files at a time and making pull requests for each. Only commit Styler as a new formatter plugin once each of these more dangerous changes has been safely committed to the codebase.

Imagine your application configures the same value twice, once with an invalid or application breaking value, and then again with a correct value, like so:

```elixir
string = "i am a string"
atom = :i_am_an_atom

config :my_app, value_must_be_an_atom: string
...
...
config :my_app, value_must_be_an_atom: atom
```

When styler sorts the configuration file, this dormant mistake can become a bug if the sorting changes the order such that the invalid value takes precedence (aka comes last)

```elixir
string = "i am a string"
atom = :i_am_an_atom

# The value that must be an atom is now a string!
config :my_app, value_must_be_an_atom: atom
config :my_app, value_must_be_an_atom: string
```

## Examples

Sorts configs by erlang term ordering:

```elixir
# Given
import Config

config :z, :x, :c
config :a, :b, :c
config :y, :x, :z
config :a, :c, :d

# Styled:
import Config

config :a, :b, :c
config :a, :c, :d

config :y, :x, :z

config :z, :x, :c
```

Non-config statements break the file up into chunks, where each chunk is sorted separately relative to itself.

```elixir
# Given
import Config

config :z, :x, :c
config :a, :b, :c
var = "value"
config :y, :x, var
config :a, :c, var

# Styled:
import Config

config :a, :b, :c
config :z, :x, :c

var = "value"

config :a, :c, var
config :y, :x, var
```
