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
