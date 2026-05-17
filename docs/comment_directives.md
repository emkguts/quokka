# Comment Directives

The `comment_directives` style implements **`# quokka:sort`** only (see `Quokka.Style.CommentDirectives`). It always runs: there is no config option to disable it. If you added `# quokka:sort` in source, Quokka will honor it on every format pass.

Other `quokka:*` comments are read by other styles:

| Comment | Style module |
|---------|----------------|
| `# quokka:sort` | `CommentDirectives` (always enabled) |
| `# quokka:skip-sort` | `Autosort` |
| `# quokka:skip-module-directives`, `# quokka:skip-module-directive-reordering`, … | `ModuleDirectives` |

## `# quokka:sort`

Opt in to sorting for a specific value. Place `# quokka:sort` on the line above the expression. This works whether or not [autosort](autosort.md) is enabled in config.

Replace `# Please keep this list sorted!` notes with `# quokka:sort` so Quokka maintains order during `mix format`.

### Examples

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
@type t :: %__MODULE__{
  c: String.t(),
  a: boolean(),
  b: pos_integer()
}
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
@type t :: %__MODULE__{
  a: boolean(),
  b: pos_integer,
  c: String.t()
}
```

### Comments while sorting

`# quokka:sort` uses the same sorting code as [autosort](autosort.md) and follows the same comment rules: comments stay with the entry they belonged to (on lines above it after formatting). See [Autosort → Comments](autosort.md#comments) for how that works for maps, defstructs, and schemas under config autosort.

For `# quokka:skip-sort` and config options, see [Autosort](autosort.md).

## Related

- [Autosort](autosort.md) — `autosort: [:map, :defstruct, :schema]` and `# quokka:skip-sort`
- [Module Directives](module_directives.md) — `use`, `alias`, `import`, skip comments, and related transforms
