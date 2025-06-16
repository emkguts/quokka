[![Hex.pm](https://img.shields.io/hexpm/v/quokka)](https://hex.pm/packages/quokka)
[![Hexdocs.pm](https://img.shields.io/badge/docs-hexdocs.pm-purple)](https://hexdocs.pm/quokka)
[![Github.com](https://github.com/smartrent/quokka/actions/workflows/ci.yml/badge.svg)](https://github.com/smartrent/quokka/actions)

# Quokka

<img src="docs/assets/quokka.jpg" alt="A happy quokka with style" width="300"/>

Quokka is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling you what's wrong, it just rewrites the code for you. Quokka is a fork of [Styler](https://github.com/adobe/elixir-styler) that checks the Credo config to determine which rules to rewrite. Many common, non-controversial Credo style rules are rewritten automatically, while the controversial Credo style rules are rewritten based on your Credo configuration so you can customize your style.

> #### WARNING {: .warning}
>
> Quokka can change the behavior of your program!
>
> In some cases, this can introduce bugs. It goes without saying, but look over your changes before committing to main :)
>
> We recommend making changes in small chunks until all of the more dangerous
> changes has been safely committed to the codebase

## Installation

Add `:quokka` as a dependency to your project's `mix.exs`:

```elixir
def deps do
  [
    {:quokka, "~> 2.7", only: [:dev, :test], runtime: false},
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

### First Run

You may want to initially run Quokka in "newline fixes only" mode. This will only fix spacing issues, making future PRs _much_ smaller and easier to digest.
See the example in the configuration section if you wish to do this.

**Speed**: Expect the first run to take some time as `Quokka` rewrites violations of styles and bottlenecks on disk I/O. Subsequent formats will take noticeably less time.

### Configuration

Quokka primarily relies on the configurations of `.formatter.exs` and `Credo` (if available).
However, there are some Quokka specific options that can also be specified
in `.formatter.exs` to fine tune your setup:

```elixir
[
  plugins: [Quokka],
  quokka: [
    autosort: [:map, :defstruct],
    inefficient_function_rewrites: true | false,
    files: %{
      included: ["lib/", ...],
      excluded: ["lib/example.ex", ...]
    },
    only: [
      # Changes to blocks of code
      :blocks
      # Comment directives such as # quokka:sort
      | :comment_directives
      # Sorting config files
      | :configs
      # Minimizes function heads
      | :defs
      # Converts deprecations
      | :deprecations
      # SPECIAL CASE: excludes all modules and only does newline fixups
      | :line_length
      # Fixes for imports, aliases, etc.
      | :module_directives
      # Various fixes for pipes
      | :pipes
      # Inefficient function rewrites, large numbers get underscores, etc.
      # Basically anything that doesn't fit into the categories above
      | :single_node
    ],
    exclude: [
      :blocks
      | :comment_directives
      | :configs
      | :defs
      | :deprecations
      | :module_directives
      | :pipes
      | :single_node
    ],
    piped_function_exclusions: [:subquery, :"Repo.update", ...]
  ]
]
```

| Option                           | Description                                                                                                                                                                                                | Default                                                             |
| -------------------------------- | ---------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- | ------------------------------------------------------------------- |
| `:autosort`                      | Sort all maps and/or defstructs in your codebase. Quokka will skip sorting maps that have comments inside them, though sorting can still be forced with `# quokka:sort`.                                   | `[]`                                                                |
| `:files`                         | Quokka gets files from `.formatter.exs[:inputs]`. However, in some cases you may need to selectively exclude/include files you wish to still run in `mix format`, but have different behavior with Quokka. | `%{included: [], excluded: []}` (all files included, none excluded) |
| `:only`                          | Only include the given modules. The special `:line_length` option excludes all changes except line length fixups.                                                                                          | `[]` (all modules included)                                         |
| `:exclude`                       | Exclude the given modules. This is just a convenience function that filters from the `:only` list.                                                                                                         | `[]` (all modules included)                                         |
| `:inefficient_function_rewrites` | Rewrite inefficient functions to more efficient form                                                                                                                                                       | `true`                                                              |
| `:piped_function_exclusions`     | Allows you to specify certain functions that won't be rewritten into a pipe. Particularly good for things like Ecto's `subquery` macro.                                                                    | `[]`                                                                |

## Credo inspired rewrites

The power of Quokka comes from utilizing the opinions you've already made with
Credo and going one step further to attempt rewriting them for you.

Below is a general overall of many Credo checks Quokka attempts to handle and
some additional useful details such as links to detailed documentation and if
the check can be configured further for fine tuning.

> #### `:controversial` Credo checks {: .tip}
>
> Quokka allows all `:controversial` Credo checks to be configurable. In many cases,
> a Credo check can also be disabled to prevent rewriting.

<!-- tabs-open -->

### Credo.Check.Consistency

| Credo Check                                                                                                       | Rewrite Description                            | Documentation                                                                       | Configurable |
| ----------------------------------------------------------------------------------------------------------------- | ---------------------------------------------- | ----------------------------------------------------------------------------------- | ------------ |
| [`.MultiAliasImportRequireUse`](https://hexdocs.pm/credo/Credo.Check.Consistency.MultiAliasImportRequireUse.html) | Expands multi-alias/import statements          | [Directive Expansion](docs/module_directives.md#directive-expansion)                |              |
| [`.ParameterPatternMatching`](https://hexdocs.pm/credo/Credo.Check.Consistency.ParameterPatternMatching.html)     | Enforces consistent parameter pattern matching | [Parameter Pattern Matching](docs/styles.md#parameter-pattern-matching-consistency) |              |

### Credo.Check.Design

| Credo Check                                                                  | Rewrite Description       | Documentation                                            | Configurable |
| ---------------------------------------------------------------------------- | ------------------------- | -------------------------------------------------------- | ------------ |
| [`.AliasUsage`](https://hexdocs.pm/credo/Credo.Check.Design.AliasUsage.html) | Extracts repeated aliases | [Alias Lifting](docs/module_directives.md#alias-lifting) | ✓            |

### Credo.Check.Readability

| Credo Check                                                                                                       | Rewrite Description                               | Documentation                                                                                  | Configurable |
| ----------------------------------------------------------------------------------------------------------------- | ------------------------------------------------- | ---------------------------------------------------------------------------------------------- | ------------ |
| [`.AliasOrder`](https://hexdocs.pm/credo/Credo.Check.Readability.AliasOrder.html)                                 | Alphabetizes module directives                    | [Module Directives](docs/module_directives.md#directive-organization)                          | ✓            |
| [`.BlockPipe`](https://hexdocs.pm/credo/Credo.Check.Readability.BlockPipe.html)                                   | (En\|dis)ables piping into blocks                 | [Pipe Chains](docs/pipes.md#pipe-start)                                                        | ✓            |
| [`.LargeNumbers`](https://hexdocs.pm/credo/Credo.Check.Readability.LargeNumbers.html)                             | Formats large numbers with underscores            | [Number Formatting](docs/styles.md#large-base-10-numbers)                                      | ✓            |
| [`.MaxLineLength`](https://hexdocs.pm/credo/Credo.Check.Readability.MaxLineLength.html)                           | Enforces maximum line length                      | [Line Length](docs/styles.md#line-length)                                                      | ✓            |
| [`.MultiAlias`](https://hexdocs.pm/credo/Credo.Check.Readability.MultiAlias.html)                                 | Expands multi-alias statements                    | [Module Directives](docs/module_directives.md#directive-expansion)                             | ✓            |
| [`.OneArityFunctionInPipe`](https://hexdocs.pm/credo/Credo.Check.Readability.OneArityFunctionInPipe.html)         | Optimizes pipe chains with single arity functions | [Pipe Chains](docs/pipes.md#add-parenthesis-to-function-calls-in-pipes)                        |              |
| [`.ParenthesesOnZeroArityDefs`](https://hexdocs.pm/credo/Credo.Check.Readability.ParenthesesOnZeroArityDefs.html) | Enforces consistent function call parentheses     | [Function Calls](docs/styles.md#add-parenthesis-to-0-arity-functions-and-macro-definitions)    | ✓            |
| [`.PipeIntoAnonymousFunctions`](https://hexdocs.pm/credo/Credo.Check.Readability.PipeIntoAnonymousFunctions.html) | Optimizes pipes with anonymous functions          | [Pipe Chains](docs/pipes.md#add-then-2-when-defining-and-calling-anonymous-functions-in-pipes) |              |
| [`.PreferImplicitTry`](https://hexdocs.pm/credo/Credo.Check.Readability.PreferImplicitTry.html)                   | Simplifies try expressions                        | [Control Flow Macros](docs/styles.md#implicit-try)                                             |              |
| [`.SinglePipe`](https://hexdocs.pm/credo/Credo.Check.Readability.SinglePipe.html)                                 | Optimizes pipe chains                             | [Pipe Chains](docs/pipes.md#unpiping-single-pipes)                                             | ✓            |
| [`.StringSigils`](https://hexdocs.pm/credo/Credo.Check.Readability.StringSigils.html)                             | Replaces strings with sigils                      | [Strings to Sigils](docs/styles.md#strings-to-sigils)                                          |              |
| [`.StrictModuleLayout`](https://hexdocs.pm/credo/Credo.Check.Readability.StrictModuleLayout.html)                 | Enforces strict module layout                     | [Module Directives](docs/module_directives.md#directive-organization)                          | ✓            |
| [`.UnnecessaryAliasExpansion`](https://hexdocs.pm/credo/Credo.Check.Readability.UnnecessaryAliasExpansion.html)   | Removes unnecessary alias expansions              | [Module Directives](docs/module_directives.md#directive-expansion)                             |              |
| [`.WithSingleClause`](https://hexdocs.pm/credo/Credo.Check.Readability.WithSingleClause.html)                     | Simplifies with statements                        | [Control Flow Macros](docs/control_flow_macros.md#with)                                        |              |

### Credo.Check.Refactor

| Credo Check                                                                                                  | Rewrite Description                     | Documentation                                                         | Configurable |
| ------------------------------------------------------------------------------------------------------------ | --------------------------------------- | --------------------------------------------------------------------- | ------------ |
| [`.CondStatements`](https://hexdocs.pm/credo/Credo.Check.Refactor.CondStatements.html)                       | Simplifies boolean expressions          | [Control Flow Macros](docs/control_flow_macros.md#cond)               |              |
| [`.FilterCount`](https://hexdocs.pm/credo/Credo.Check.Refactor.FilterCount.html)                             | Optimizes filter + count operations     | [Styles](docs/styles.md#filter-count)                                 |              |
| [`.MapInto`](https://hexdocs.pm/credo/Credo.Check.Refactor.MapInto.html)                                     | Optimizes map + into operations         | [Styles](docs/styles.md#map-into)                                     |              |
| [`.MapJoin`](https://hexdocs.pm/credo/Credo.Check.Refactor.MapJoin.html)                                     | Optimizes map + join operations         | [Styles](docs/styles.md#map-join)                                     |              |
| [`.NegatedConditionsInUnless`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsInUnless.html) | Simplifies negated conditions in unless | [Control Flow Macros](docs/control_flow_macros.md#if-and-unless)      |              |
| [`.NegatedConditionsWithElse`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsWithElse.html) | Simplifies negated conditions with else | [Control Flow Macros](docs/control_flow_macros.md#negation-inversion) |              |
| [`.PipeChainStart`](https://hexdocs.pm/credo/Credo.Check.Refactor.PipeChainStart.html)                       | Optimizes pipe chain start              | [Pipe Chains](docs/pipes.md#pipe-start)                               |              |
| [`.RedundantWithClauseResult`](https://hexdocs.pm/credo/Credo.Check.Refactor.RedundantWithClauseResult.html) | Removes redundant with clause results   | [Control Flow Macros](docs/control_flow_macros.md#with)               |              |
| [`.UnlessWithElse`](https://hexdocs.pm/credo/Credo.Check.Refactor.UnlessWithElse.html)                       | Simplifies unless with else             | [Control Flow Macros](docs/control_flow_macros.md#if-and-unless)      |              |
| [`.WithClauses`](https://hexdocs.pm/credo/Credo.Check.Refactor.WithClauses.html)                             | Optimizes with clauses                  | [Control Flow Macros](docs/control_flow_macros.md#with)               |              |

### Credo.Check.Warning


| Credo Check                                                                                                  | Rewrite Description                             | Documentation                                                         | Configurable |
| ------------------------------------------------------------------------------------------------------------ | ----------------------------------------------- | --------------------------------------------------------------------- | ------------ |
| [`.ExpensiveEmptyEnumCheck`](https://hexdocs.pm/credo/Credo.Check.Warning.ExpensiveEmptyEnumCheck.html)      | Rewrites slow checks of enum emptiness          | [Styles](docs/styles.md#empty-enum-checks)                  |              |

<!-- tabs-close -->

## License

Quokka is licensed under the Apache 2.0 license. See the [LICENSE file](LICENSE) for more details.
