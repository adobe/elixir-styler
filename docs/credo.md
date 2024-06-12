### Credo Rules Styler Replaces

If you're using Credo and Styler, **we recommend disabling these rules in `.credo.exs`** to save on unnecessary checks in CI.
As long as you're running `mix format --check-formatted` in CI, Styler will be enforcing the rules for you, so checking them with Credo is redundant.

Disabling the rules means updating your `.credo.exs` depending on your configuration:

- if you're using `checks: %{enabled: [...]}`, ensure none of the checks are listed in your enabled checks
- if you're using `checks: %{disabled: [...]}`, copy/paste the snippet below into the list
- if you're using `checks: [...]`, copy/paste the snippet below into the list and ensure none of the checks appear earlier in the list

```elixir
# Styler Rewrites
#
# The following rules are automatically rewritten by Styler and so disabled here to save time
# Some of the rules have `priority: :high`, meaning Credo runs them unless we explicitly disable them
# (removing them from this file wouldn't be enough, the `false` is required)
#
{Credo.Check.Consistency.MultiAliasImportRequireUse, false},
{Credo.Check.Consistency.ParameterPatternMatching, false},
{Credo.Check.Design.AliasUsage, false},
{Credo.Check.Readability.AliasOrder, false},
{Credo.Check.Readability.BlockPipe, false},
{Credo.Check.Readability.LargeNumbers, false},
{Credo.Check.Readability.ModuleDoc, false},
{Credo.Check.Readability.MultiAlias, false},
{Credo.Check.Readability.OneArityFunctionInPipe, false},
{Credo.Check.Readability.ParenthesesOnZeroArityDefs, false},
{Credo.Check.Readability.PipeIntoAnonymousFunctions, false},
{Credo.Check.Readability.PreferImplicitTry, false},
{Credo.Check.Readability.SinglePipe, false},
{Credo.Check.Readability.StrictModuleLayout, false},
{Credo.Check.Readability.StringSigils, false},
{Credo.Check.Readability.UnnecessaryAliasExpansion, false},
{Credo.Check.Readability.WithSingleClause, false},
{Credo.Check.Refactor.CaseTrivialMatches, false},
{Credo.Check.Refactor.CondStatements, false},
{Credo.Check.Refactor.FilterCount, false},
{Credo.Check.Refactor.MapInto, false},
{Credo.Check.Refactor.MapJoin, false},
{Credo.Check.Refactor.NegatedConditionsInUnless, false},
{Credo.Check.Refactor.NegatedConditionsWithElse, false},
{Credo.Check.Refactor.PipeChainStart, false},
{Credo.Check.Refactor.RedundantWithClauseResult, false},
{Credo.Check.Refactor.UnlessWithElse, false},
{Credo.Check.Refactor.WithClauses, false},
 ```
