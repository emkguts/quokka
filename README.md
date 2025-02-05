[![Hex.pm](https://img.shields.io/hexpm/v/quokka)](https://hex.pm/packages/quokka)
[![Hexdocs.pm](https://img.shields.io/badge/docs-hexdocs.pm-purple)](https://hexdocs.pm/quokka)
[![Github.com](https://github.com/smartrent/quokka/actions/workflows/ci.yml/badge.svg)](https://github.com/smartrent/quokka/actions)

# Quokka

Quokka is an Elixir formatter plugin that's combination of `mix format` and `mix credo`, except instead of telling
you what's wrong, it just rewrites the code for you to fit its style rules.

Quokka is a fork of [Styler](https://github.com/adobe/styler) that checks the credo config to determine which rules to rewrite.

## Features

- auto-fixes [many credo rules](docs/credo.md), meaning you can turn them off to speed credo up
- [keeps a strict module layout](docs/module_directives.md#directive-organization)
  - alphabetizes module directives
- [extracts repeated aliases](docs/module_directives.md#alias-lifting)
- [makes your pipe chains pretty as can be](docs/pipes.md)
  - pipes and unpipes function calls based on the number of calls
  - optimizes standard library calls (`a |> Enum.map(m) |> Enum.into(Map.new)` => `Map.new(a, m)`)
- replaces strings with sigils when the string has many escaped quotes
- [reorders configuration in config files](docs/configs.md)
- [expands multi-alias/import statements](docs/module_directives.md#directive-expansion)
- [enforces consistent function call parentheses](docs/function_calls.md)
- [ensures consistent spacing around operators](docs/operators.md)
- [formats documentation comments](docs/docs.md)
- [removes unnecessary parentheses](docs/parentheses.md)
- [simplifies boolean expressions](docs/boolean_simplification.md)
- [enforces consistent module attribute usage](docs/module_attributes.md)
- [formats and organizes typespecs](docs/typespecs.md)
- ... and many more style improvements

[See our Rewrites documentation on hexdocs](https://hexdocs.pm/quokka/styles.html)

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

**Speed**: Expect the first run to take some time as `Quokka` rewrites violations of styles and bottlenecks on disk I/O. Subsequent formats formats won't take noticeably more time.

### Configuration

Quokka can be configured in your `.formatter.exs` file

```elixir
[
  plugins: [Quokka],
  quokka: [
    inefficient_function_rewrites: true | false,
    reorder_configs: true | false
  ]
]
```

Quokka has several configuration options:

- `:reorder_configs`, which controls whether or not the configs in your `config/*.exs` files are alphabetized. This is true by default.
- `:inefficient_function_rewrites`, which controls whether or not Quokka will rewrite deprecated functions to their new form. This is true by default.

## WARNING: Quokka can change the behaviour of your program!

In some cases, this can introduce bugs. It goes without saying, but look over your changes before committing to main :)

Some ways Quokka can change your program:

- [`with` statement rewrites](https://github.com/adobe/elixir-styler/issues/186)
- [config file sorting](https://hexdocs.pm/quokka/mix_configs.html#this-can-break-your-program)
- and likely other ways. stay safe out there!

## License

Quokka is licensed under the Apache 2.0 license. See the [LICENSE file](LICENSE) for more details.
