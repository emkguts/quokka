# Changelog

Quokka follows [Semantic Versioning](https://semver.org) and
[Common Changelog: Guiding Principles](https://common-changelog.org/#12-guiding-principles)

## [Unreleased]

## [2.12.0] - 2026-02-08

### Breaking Changes

- Multi-alias sorting now matches Credo.Check.Readability.AliasOrder behavior by comparing the first child's full path instead of parent module only. This fixes compatibility with Credo 1.7.13+, which fixed a bug that now properly checks multi-alias ordering. Projects using Credo 1.7.12 or earlier may see new alias ordering changes when formatting. Upgrading to Credo 1.7.13+ is recommended for proper alias order checking.

### Improvements

- Automatically fix `Credo.Check.Refactor.UtcNowTruncate` by rewriting `DateTime.utc_now() |> DateTime.truncate(precision)` to `DateTime.utc_now(precision)`.
- Transform `Timex.today()` to `Date.utc_today()`.
- Rewrite `Map/Keyword.get(lhs, key, nil)` to `Map/Keyword.get(lhs, key)`.
- Consecutive `Keyword.drop` or `Keyword.delete` rewrite to `Keyword.drop` as part of inefficient function rewrites.
- Respect Credo's NegativeConditionsWithElse configuration.
- Add comment directive `# quokka:skip-module-directive-reordering` for skipping module directive reordering to skip module directive reordering but still lift aliases, multi-alias expansion, etc.
- Support piped function exclusions in SinglePipe rewrite. 
- Support rewriting pipes within a `case ... do` block to instead pipe into case. Add `exclude: [:pipe_into_case]` to opt out of this behavior.

### Fixes

- Fix invalid inefficient function rewrites on Map.reduce arguments.
- Sort nested module directives (e.g., `alias A.{B, E, C}` will be sorted to `alias A.{B, C, E}`).

### Upgrades

- Upgrade credo to 1.7.16
- Add Elixir 1.19.1 and OTP 28.1.1 to CI checks

### Deprecations

- Soft deprecate `quokka:skip-module-reordering` in favor of `quokka:skip-module-directives`.

## [2.11.2] - 2025-08-27

### Fixes

- Fix crash in sorting when schema definition occurs through a macro.

## [2.11.1] - 2025-08-26

### Fixes

- Improved error handling
- Handle rewriting anonymous function captures of variables

## [2.11.0] - 2025-08-20

### Improvements

- Support `:only` config option for `Credo.Check.Design.AliasUsage`.
- Rewrite multiple `Map.delete` to `Map.drop`.
- Rewrite `&my_func(&1)` => `&my_func/1` where relevant.
- Rewrite `Enum.filter(fun) |> List.first([default])` => `Enum.find([default], fun)`

### Fixes

- Set default Elixir version as empty string for language server compatibility.
- Do not dealias within moduledocs depending on the module layout order.
- Properly autosort embedded schema.
- Strict module layout styling fail for non-existent keys.

## [2.10.0] - 2025-07-29

### Improvements

- Rewrite `refute not` => `assert`

## [2.9.1] - 2025-07-13

### Fixes

- Include ranges in numeric sorting.

## [2.9.0] - 2025-07-13

### Improvements

- Rewrite inefficient Repo existence checks (`Repo.one` => `Repo.exists?` where appropriate)

#### New rewrite type: tests

Quokka will style your tests. For now, the main rewrite is `assert not` gets rewritten to `refute`. If you don't want this rewrite, add `exclude: [:tests]`.

### Fixes

- In autosort, sort numeric keys naturally (ie, 1, 2, 10 instead of 1, 10, 2).
- Update mix.exs changelog link to use hexdocs.

## [2.8.1] - 2025-07-07

### Fixes

- Don't fail when credo not used in project.

## [2.8.0] - 2025-07-01

### Improvements

- Leverage the Elixir version in the project to determine deprecation rewrites (instead of system version).
- Add `exclude: [nums_with_underscores]` config to ignore numbers with underscores. (Don't style 100_00 as 10_000).
- Add `exclude: [:autosort_ecto]` config to skip autosorting within Ecto queries.
- Rewrite ExpensiveEmptyEnumCheck for Enum.count/2 (previously only supported Enum.count/1)
- Rewrite ExpensiveEmptyEnumCheck in guards
- Autosort efficiency improvements

### Fixes

- Run formatter on ignored files. Previously, ignored files weren't getting formatted by default formatter.
- Add changelog to Hex package metadata

### Deprecations

- `piped_function_exclusions` is now deprecated. Use `exclude: [piped_functions: []]`
- `inefficient_function_rewrites` is now deprecated. Use `exclude: [inefficient_functions]`

## [2.7.1] - 2025-06-16

### Fixes

- Don't rewrite length() inside guard statements
- Don't add additional line to blank files (fixes issue Credo.Check.Readability.RedundantBlankLines for whitespace only files)

## [2.7.0] - 2025-06-15

### Improvements

- Add rewrites for ExpensiveEmptyEnumCheck

## [2.6.0] - 2025-04-17

### Improvements

- Use the elixir version from `mix.exs` instead of the system version, since these two might not always match, especially if you work in many different repos.

## [2.5.2] - 2025-04-09

### Fixes

- Don't throw errors when styling an empty module

## [2.5.1] - 2025-04-09

### Fixes

- Fix pipe chain start with alias lifting exceptions. When an alias is excluded from lifting, it was not properly identifying invalid pipe chain start.

## [2.5.0] - 2025-04-01

### Improvements

- `if`: drop empty `do` bodies like `if a, do: nil, else: b` => `if !a, do: b`
- `to_timeout/1` rewrites to use the next largest unit in some simple instances

  ```elixir
  # before
  to_timeout(second: 60 * m)
  to_timeout(day: 7)
  # after
  to_timeout(minute: m)
  to_timeout(week: 1)
  ```

### Fixes

- fixed crash when `Credo.Check.Design.AliasUsage` opts `excluded_namespaces` and `excluded_lastnames` were provided.
- fixed quokka raising when encountering invalid function definition ast

## [2.4.1] - 2025-03-11

### Fixes

- Change default schema autosort order to put fields first. When fields don't come first, this can cause errors because some association fields require the field already being defined.

## [2.4.0] - 2025-03-10

### Improvements

- Add option to autosort schemas. `:schema` is now a supported option in `autosort`. Furthermore, order can be specified as `autosort: [schema: [:field, :many_to_many, :has_many, ...]]`.

## [2.3.1] - 2025-03-06

### Fixes

- Fix alias lifting when a variable matches the directive. Before, if you named a variable `import` or `use` (why would you do that?), it would break the alias lifting.

## [2.3.0] - 2025-03-06

### Improvements

Credo doesn't warn about alias lifting for `behaviour, use, import` directives (unless there are aliases inside opts). Therefore, to match credo:

- Don't lift `behaviour` aliases at all.
- Only lift `use` and `import` aliases if they were going to be lifted anyways (credo wouldn't yell either way, but it seems sensible to lift an alias if it's already lifted).

## [2.2.0] - 2025-03-04

### Improvements

- Check `.formatter.exs` for `line_length` config. Use the minimum of the credo and formatter `line_length`.

### Fixes

- Do not sort `use` directives. Some `use` directives depend on others coming first, so sorting them can break code. This bug was introduced in 2.1.0.

## [2.1.0] - 2025-03-02

### Improvements

#### New options

- `autosort`: Sort all maps and/or defstructs in your codebase. Quokka will skip sorting maps that have comments inside them, though sorting can still be forced with `# quokka:sort`

- `piped_function_exclusions` allows you to specify certain functions that won't be rewritten into a pipe. Particularly good for things like Ecto's `subquery` macro. Example:

```elixir
# Before
subquery(
  base_query()
  |> select([:id, :name])
  |> where([_, id], id > 100)
  |> limit(1)
)
```

would normally be rewritten to:

```elixir
  base_query()
  |> select([:id, :name])
  |> where([_, id], id > 100)
  |> limit(1)
  |> subquery()
```

but with the option set like this, it will not be rewritten:

```elixir
# .formatter.exs
quokka: [
  piped_function_exclusions: [:"Ecto.Query.subquery"]
]
```

#### Deprecations

- For elixir 1.18 and above, Quokka will rewrite `%Foo{x | y} => %{x | y}`
- For elixir 1.17 and above, Quokka will replace `:timer.units(x)` with `to_time(unit: x)`

### Fixes

- Lift aliases that were already lifted
- Lift aliases from inside module directives like `use` if the directive type comes after the alias.
- `with` redundant body + non-arrow behind redundant clause

## [2.0.0] - 2025-02-20

### Improvements

#### Configuration filtering with :only and :exclude

Quokka now supports filtering which rewrites to apply using the `:only` and `:exclude` configuration options. This allows teams to gradually adopt Quokka's rewrites by explicitly including or excluding specific ones.

Example configuration in `.formatter.exs`:

```elixir
[
  # Only apply these specific rewrites
  only: [:pipes, :aliases, :line_length],

  # Or exclude specific rewrites
  exclude: [:sort_directives]
]
```

See the documentation for a complete list of available rewrite options.

### Breaking Changes

- Removed `newline_fixes_only` configuration option in favor of using `only: [:line_length]`
- Removed `reorder_configs` configuration option in favor of using `only: [:configs]`
- Removed `rewrite_deprecations` configuration option in favor of using `only: [:deprecations]`

## [1.1.0] - 2025-02-14

### Improvements

#### Line length formatting only

In order to phase this into large codebases, Quokka now supports formatting only the line length, the idea being that it is easier to review a diff where one commit is just compressing vertical code and the following is the substantive rewrites -- aka the rewrites that change the AST. In order to use this feature, use `newline_fixes_only: true | false` in the config.

##### `# quokka:sort` Quokka's first comment directive

Quokka will now keep a user-designated list or wordlist (`~w` sigil) sorted as part of formatting via the use of comments. Elements of the list are sorted by their string representation. It also works with maps, key-value pairs (sort by key), and `defstruct`, and even arbitrary ast nodes with a `do end` block.

The intention is to remove comments to humans, like `# Please keep this list sorted!`, in favor of comments to robots: `# quokka:sort`. Personally speaking, Quokka is much better at alphabetical-order than I ever will be.

To use the new directive, put it on the line before a list or wordlist.

This example:

```elixir
# quokka:sort
[:c, :a, :b]

# quokka:sort
~w(a list of words)

# quokka:sort
@country_codes ~w(
  en_US
  po_PO
  fr_CA
  ja_JP
)

# quokka:sort
a_var =
  [
    Modules,
    In,
    A,
    List
  ]

  # quokka:sort
  my_macro "some arg" do
    another_macro :q
    another_macro :w
    another_macro :e
    another_macro :r
    another_macro :t
    another_macro :y
  end
```

Would yield:

```elixir
# quokka:sort
[:a, :b, :c]

# quokka:sort
~w(a list of words)

# quokka:sort
@country_codes ~w(
  en_US
  fr_CA
  ja_JP
  po_PO
)

# quokka:sort
a_var =
  [
    A,
    In,
    List,
    Modules
  ]

# quokka:sort
my_macro "some arg" do
  another_macro :e
  another_macro :q
  another_macro :r
  another_macro :t
  another_macro :w
  another_macro :y
end
```

#### Other improvements

- General improvements around conflict detection, lifting in more correct places and fewer incorrect places.
- Use knowledge of existing aliases to shorten invocations.

  example:
  alias A.B.C

        A.B.C.foo()
        A.B.C.bar()
        A.B.C.baz()

  becomes:
  alias A.B.C

        C.foo()
        C.bar()
        C.baz()

- Config Sorting: improve comment handling when only sorting a few nodes.
- Pipes: pipe-ifies when first arg to a function is a pipe. reach out if this happens in unstylish places in your code.
- Pipes: unpiping assignments will make the assignment one-line when possible
- Deprecations: 1.18 deprecations
  - `List.zip` => `Enum.zip`
  - `first..last = range` => `first..last//_ = range`

### Fixes

- Support the credo config of the format `checks: %{enabled: [...], disabled: [...]}`, whereas previously it expected `checks: [...]}`
- Pipes: optimizations are less likely to move comments
- Don't pipify when the call is itself in a pipe (aka don't touch a |> b(c |> d() |>e()) |> f())

## [1.0.0] - 2025-02-10

Quokka is inspired by the wonderful [`elixir-styler`](https://github.com/adobe/elixir-styler) :heart:

It maintains the same directive that consistent coding standards can help teams
iterate quickly, but allows a few more affordances
[via `.credo.exs` configuration](https://hexdocs.pm/credo/config_file.html).
This allows users with an already fine-tuned `.credo.exs` config to enjoy
the automatic rewrites and strong opinions of Quokka

More details about specific Credo rewrites and their configurability can be
found in [Quokka: Credo inspired rewrites](https://hexdocs.pm/quokka/readme.html#credo-inspired-rewrites).

Adoption of opinionated code changes can be hard in larger code bases, so
Quokka allows a few configuration options in `.formatter.exs` to help
isolate big sets of potentially controversial or code breaking changes that
may need time for adoption. However, these may be removed in a future release.
See [Quokka: Configuration](https://hexdocs.pm/quokka/readme.html#configuration)
for more details.
