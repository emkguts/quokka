# Comment Directives

## Maintain static list order via `# quokka:sort`

Quokka can keep static values sorted for your team as part of its formatting pass. To instruct it to do so, replace any `# Please keep this list sorted!` notes you wrote to your teammates with `# quokka:sort`.

#### Examples

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
```

## Autosort

Quokka can autosort maps and defstructs. To enable this feature, set `autosort: [:map, :defstruct]` in the config. Quokka will skip sorting maps that have comments inside them, though sorting can still be forced with `# quokka:sort`. Finally, when `sort_all_maps` is true, a specific map can be skipped by adding `# quokka:skip-sort` on the line above the map.

#### Examples

When `autosort: [:map]` is enabled:
```elixir
# quokka:skip-sort
%{c: 3, b: 2, a: 1}

%{c: 3, b: 2, a: 1}

%{
  c: 3,
  b: 2,
  # this needs to come last
  a: 1
}

# quokka:sort
%{
  c: 3,
  b: 2,
  # this needs to come last
  a: 1
}
```

would yield

```elixir
# quokka:skip-sort
%{c: 3, b: 2, a: 1}

%{a: 1, b: 2, c: 3}

%{
  c: 3,
  b: 2,
  # this needs to come last
  a: 1
}

# quokka:sort
%{
  # this needs to come last
  a: 1,
  b: 2,
  c: 3
}
```