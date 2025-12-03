# Style Table of Contents

Styler performs myriad rewrites, logically broken apart into the following groups:

- [Comment Directives](./comment_directives.md): leave comments to Styler instructing it to perform a task
- [Control Flow Macros](./control_flow_macros.md): styles modifying `case`, `if`, `unless`, `cond` and `with` statements
- [Elixir Deprecations](./deprecations.md): Styles which automate the replacement or updating of code deprecated by new Elixir releases
- [General Styles](./general_styles.md): general simple 1-1 rewrites that require a minimum amount of awareness of the AST
- [Mix Configs](./mix_configs.md): Styler applies order to chaos by organizing mix `config ...` stanzas
- [Module Directives](./module_directives.md): Styles for `alias`, `use`, `import`, `require`, as well as alias lifting and alias application.
- [Pipes](./pipes.md): Styles for the famous Elixir pipe `|>`, including optimizations for piping standard library functions

Finally, if you're using Credo [see our documentation](./credo.md) about rules that can be disabled in Credo because Styler automatically enforces them for you, saving a modicum of CI time.
