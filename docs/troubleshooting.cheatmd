### Troubleshooting: Compilation broke due to Module Directive rearrangement

Styler naively moves module attributes, which can break compilation. For now, the only fix is some elbow grease.

#### Module Attribute dependency

Another common compilation break on the first run is a `@moduledoc` that depended on another module attribute which
was moved below it.

For example, given the following broken code after an initial `mix format`:

```elixir
defmodule MyGreatLibrary do
  @moduledoc make_pretty_docs(@library_options)
  use OptionsMagic, my_opts: @library_options

  @library_options [ ... ]
end
```

You can fix the code by moving the static value outside of the module into a naked variable and then reference it in the module. (Note that `use` macros need an `unquote` wrapping the variable!)

Yes, this is a thing you can do in a `.ex` file =)

```elixir
library_options = [ ... ]

defmodule MyGreatLibrary do
  @moduledoc make_pretty_docs(library_options)
  use OptionsMagic, my_opts: unquote(library_options)

  @library_options library_options
end
```
