[![Hex.pm](https://img.shields.io/hexpm/v/quokka)](https://hex.pm/packages/quokka)
[![Hexdocs.pm](https://img.shields.io/badge/docs-hexdocs.pm-purple)](https://hexdocs.pm/quokka)
[![Github.com](https://github.com/smartrent/quokka/actions/workflows/ci.yml/badge.svg)](https://github.com/smartrent/quokka/actions)

# Quokka

<img src="docs/assets/quokka.png" alt="A happy quokka with style" width="300"/>  

Quokka is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling you what's wrong, it just rewrites the code for you. Quokka is a fork of [Styler](https://github.com/adobe/styler) that checks the Credo config to determine which rules to rewrite. Many common, non-controversial Credo style rules are rewritten automatically, while the controversial Credo style rules are rewritten based on your Credo configuration so you can customize your style.

> #### WARNING {: .warning}
> Quokka can change the behavior of your program!
> 
> In some cases, this can introduce bugs. It goes without saying, but look over your changes before committing to main :)
> 
> Some ways Quokka can change your program:
> 
> - [`with` statement rewrites](https://github.com/adobe/elixir-styler/issues/186)
> - [config file sorting](https://hexdocs.pm/styler/mix_configs.html#this-can-break-your-program) -- But this can be disabled.
> - and likely other ways. stay safe out there!

## Installation

Add `:quokka` as a dependency to your project's `mix.exs`:

```elixir
def deps do
  [
    {:quokka, "~> 0.1", only: [:dev, :test], runtime: false},
  ]
end
```

Then add `Quokka` as a plugin to your `.formatter.exs` file

```elixir
[
  plugins: [Quokka]
]
```

And that's it! Now when you run `mix format` you'll also get the benefits of Quokka's Stylish Stylings.

**Speed**: Expect the first run to take some time as `Quokka` rewrites violations of styles and bottlenecks on disk I/O. Subsequent formats will take noticeably less time.

### Configuration

Quokka primarily relies on the configurations of `.formatter.exs` and `Credo` (if available).
However, there are some Quokka specific options that can also be specified
in `.formatter.exs` to fine tune your setup:

```elixir
[
  plugins: [Quokka],
  quokka: [
    inefficient_function_rewrites: true | false,
    reorder_configs: true | false,
    rewrite_deprecations: true | false,
    files: %{
      included: ["lib/", ...],
      excluded: ["lib/example.ex", ...]
    }
  ]
]
```
| Option | Description | Default |
| --- | --- | --- |
| `:files` | Quokka gets files from `.formatter.exs[:inputs]`. However, in some cases you may need to selectively exclude/include files you wish to still run in `mix format`, but have different behavior with Quokka. | `%{included: [], excluded: []}` (all files included, none excluded) |
| `:inefficient_function_rewrites` | Rewrite inefficient functions to more efficient form | `true` |
| `:reorder_configs` | Alphabetize `config` by key in `config/*.exs` files | `true` |
| `:rewrite_deprecations` | Rewrite deprecated functions to their new form | `true` |

## Rewrites

| Credo Check | Rewrite Description | Documentation | Configurable |
|-------------|-------------------|---------------|--------------|
| [`Credo.Check.Consistency.MultiAliasImportRequireUse`](https://hexdocs.pm/credo/Credo.Check.Consistency.MultiAliasImportRequireUse.html) | Expands multi-alias/import statements | [Directive Expansion](docs/module_directives.md#directive-expansion) | |
| [`Credo.Check.Consistency.ParameterPatternMatching`](https://hexdocs.pm/credo/Credo.Check.Consistency.ParameterPatternMatching.html) | Enforces consistent parameter pattern matching | [Parameter Pattern Matching](docs/styles.md#parameter-pattern-matching-consistency) | |
| [`Credo.Check.Design.AliasUsage`](https://hexdocs.pm/credo/Credo.Check.Design.AliasUsage.html) | Extracts repeated aliases | [Alias Lifting](docs/module_directives.md#alias-lifting) | ✓ |
| [`Credo.Check.Readability.AliasOrder`](https://hexdocs.pm/credo/Credo.Check.Readability.AliasOrder.html) | Alphabetizes module directives | [Module Directives](docs/module_directives.md#directive-organization) | ✓ |
| [`Credo.Check.Readability.BlockPipe`](https://hexdocs.pm/credo/Credo.Check.Readability.BlockPipe.html) | (En\|dis)ables piping into blocks | [Pipe Chains](docs/pipes.md#pipe-start) | ✓ |
| [`Credo.Check.Readability.LargeNumbers`](https://hexdocs.pm/credo/Credo.Check.Readability.LargeNumbers.html) | Formats large numbers with underscores | [Number Formatting](docs/styles.md#large-base-10-numbers) | ✓ |
| [`Credo.Check.Readability.MaxLineLength`](https://hexdocs.pm/credo/Credo.Check.Readability.MaxLineLength.html) | Enforces maximum line length | [Line Length](docs/styles.md#line-length) | ✓ |
| [`Credo.Check.Readability.MultiAlias`](https://hexdocs.pm/credo/Credo.Check.Readability.MultiAlias.html) | Expands multi-alias statements | [Module Directives](docs/module_directives.md#directive-expansion) | ✓ |
| [`Credo.Check.Readability.OneArityFunctionInPipe`](https://hexdocs.pm/credo/Credo.Check.Readability.OneArityFunctionInPipe.html) | Optimizes pipe chains with single arity functions | [Pipe Chains](docs/pipes.md#add-parenthesis-to-function-calls-in-pipes) | |
| [`Credo.Check.Readability.ParenthesesOnZeroArityDefs`](https://hexdocs.pm/credo/Credo.Check.Readability.ParenthesesOnZeroArityDefs.html) | Enforces consistent function call parentheses | [Function Calls](docs/styles.md#add-parenthesis-to-0-arity-functions-and-macro-definitions) | ✓ |
| [`Credo.Check.Readability.PipeIntoAnonymousFunctions`](https://hexdocs.pm/credo/Credo.Check.Readability.PipeIntoAnonymousFunctions.html) | Optimizes pipes with anonymous functions | [Pipe Chains](docs/pipes.md#add-then-2-when-defining-and-calling-anonymous-functions-in-pipes) | |
| [`Credo.Check.Readability.PreferImplicitTry`](https://hexdocs.pm/credo/Credo.Check.Readability.PreferImplicitTry.html) | Simplifies try expressions | [Control Flow Macros](docs/styles.md#implicit-try) | |
| [`Credo.Check.Readability.SinglePipe`](https://hexdocs.pm/credo/Credo.Check.Readability.SinglePipe.html) | Optimizes pipe chains | [Pipe Chains](docs/pipes.md#unpiping-single-pipes) | ✓ |
| [`Credo.Check.Readability.StringSigils`](https://hexdocs.pm/credo/Credo.Check.Readability.StringSigils.html) | Replaces strings with sigils | [Strings to Sigils](docs/styles.md#strings-to-sigils) | |
| [`Credo.Check.Readability.StrictModuleLayout`](https://hexdocs.pm/credo/Credo.Check.Readability.StrictModuleLayout.html) | Enforces strict module layout | [Module Directives](docs/module_directives.md#directive-organization) | ✓ |
| [`Credo.Check.Readability.UnnecessaryAliasExpansion`](https://hexdocs.pm/credo/Credo.Check.Readability.UnnecessaryAliasExpansion.html) | Removes unnecessary alias expansions | [Module Directives](docs/module_directives.md#directive-expansion) | |
| [`Credo.Check.Readability.WithSingleClause`](https://hexdocs.pm/credo/Credo.Check.Readability.WithSingleClause.html) | Simplifies with statements | [Control Flow Macros](docs/control_flow_macros.md#with) | |
| [`Credo.Check.Refactor.CondStatements`](https://hexdocs.pm/credo/Credo.Check.Refactor.CondStatements.html) | Simplifies boolean expressions | [Control Flow Macros](docs/control_flow_macros.md#cond) | |
| [`Credo.Check.Refactor.FilterCount`](https://hexdocs.pm/credo/Credo.Check.Refactor.FilterCount.html) | Optimizes filter + count operations | [Styles](docs/styles.md#filter-count) | |
| [`Credo.Check.Refactor.MapInto`](https://hexdocs.pm/credo/Credo.Check.Refactor.MapInto.html) | Optimizes map + into operations | [Styles](docs/styles.md#map-into) | |
| [`Credo.Check.Refactor.MapJoin`](https://hexdocs.pm/credo/Credo.Check.Refactor.MapJoin.html) | Optimizes map + join operations | [Styles](docs/styles.md#map-join) | |
| [`Credo.Check.Refactor.NegatedConditionsInUnless`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsInUnless.html) | Simplifies negated conditions in unless | [Control Flow Macros](docs/control_flow_macros.md#if-and-unless) | |
| [`Credo.Check.Refactor.NegatedConditionsWithElse`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsWithElse.html) | Simplifies negated conditions with else | [Control Flow Macros](docs/control_flow_macros.md#negation-inversion) | |
| [`Credo.Check.Refactor.PipeChainStart`](https://hexdocs.pm/credo/Credo.Check.Refactor.PipeChainStart.html) | Optimizes pipe chain start | [Pipe Chains](docs/pipes.md#pipe-start) | |
| [`Credo.Check.Refactor.RedundantWithClauseResult`](https://hexdocs.pm/credo/Credo.Check.Refactor.RedundantWithClauseResult.html) | Removes redundant with clause results | [Control Flow Macros](docs/control_flow_macros.md#with) | |
| [`Credo.Check.Refactor.UnlessWithElse`](https://hexdocs.pm/credo/Credo.Check.Refactor.UnlessWithElse.html) | Simplifies unless with else | [Control Flow Macros](docs/control_flow_macros.md#if-and-unless) | |
| [`Credo.Check.Refactor.WithClauses`](https://hexdocs.pm/credo/Credo.Check.Refactor.WithClauses.html) | Optimizes with clauses | [Control Flow Macros](docs/control_flow_macros.md#with) | |
| - | Alphabetizes configuration in config files | [Config Files](docs/mix_configs.md) | ✓ |
| - | Rewrites deprecated functions | [Deprecation Rewrites](docs/styles.md#elixir-deprecation-rewrites) | ✓ |
| - | Miscellaneous inefficient function calls | [Inefficient Function Rewrites](docs/styles.md#inefficient-function-rewrites) | ✓ |
| - | Miscellaneous with rewrites | [With Rewrites](docs/control_flow_macros.md#with) | |
| - | Piped function optimizations | [Pipe Chains](docs/pipes.md#piped-function-optimizations) | |


[See our Rewrites documentation on hexdocs](https://hexdocs.pm/quokka/styles.html)

## License

Quokka is licensed under the Apache 2.0 license. See the [LICENSE file](LICENSE) for more details.
