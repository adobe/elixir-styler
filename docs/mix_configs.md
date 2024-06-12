# Mix Configs

Mix Config files have their config stanzas sorted. Similar to the sorting of aliases, this delivers consistency to an otherwise arbitrary world, and can even help catch bugs like configuring the same key multiple times.

A file is considered a config file if

1. its path matches `config/.*\.exs` or `rel/overlays/.*\.exs`
2. the file has `import Config`

Once a file is detected as a mix config, its `config/2,3` stanzas are grouped and ordered like so:

- group config stanzas separated by assignments (`x = y`) together
- sort each group according to erlang term sorting
- move all existing assignments between the config stanzas to above the stanzas (without changing their ordering)

## Examples

TODOs
