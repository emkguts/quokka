# Changelog

Quokka follows [Semantic Versioning](https://semver.org) and
[Common Changelog: Guiding Principles](https://common-changelog.org/#12-guiding-principles)

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
