# Autosort

Config-driven sorting for maps, `defstruct`s, and Ecto schemas.

## Autosort vs `# quokka:sort`

Quokka has two complementary ways to sort values. Both use the same sorting implementation. They differ in how they handle comments: config autosort skips any entity that contains comments, while `# quokka:sort` always sorts and attaches comments to the entry they belong to.

| | Config autosort | `# quokka:sort` |
|---|---|---|
| **How to enable** | `autosort: [:map, :defstruct, :schema]` in `.formatter.exs` | Place `# quokka:sort` on the line above a value |
| **What it sorts** | All matching values in the codebase | Only values you annotate (lists, sigils, `@type` maps, and so on) |
| **Opt out** | `# quokka:skip-sort` on a specific value, or `exclude: [:autosort]` | Not applicable — annotated values are always sorted |
| **`:only` / `:exclude` style** | `:autosort` | Not configurable — `# quokka:sort` always runs |

See [Comment Directives](comment_directives.md) for `# quokka:sort` examples.

> #### Upgrading from 2.12.x {: .tip}
>
> Prior to 2.13.0, config-driven autosort and `# quokka:sort` were both controlled via `:comment_directives` in `:only` or `:exclude`. They are now separate:
>
> - Use `:autosort` in `:only` or `:exclude` to control config-driven sorting.
> - `# quokka:sort` always runs and cannot be disabled.
> - `exclude: [:comment_directives]` has no effect and logs a warning.

Enable config autosort in `.formatter.exs`:

```elixir
[
  plugins: [Quokka],
  quokka: [
    autosort: [:map, :defstruct, :schema]
  ]
]
```

Schema field order can be customized:

```elixir
autosort: [:map, schema: [:field, :belongs_to]]
```

The default schema order is: `[:field, :belongs_to, :has_many, :has_one, :many_to_many, :embeds_many, :embeds_one]`.

## Disabling autosort

| Goal | Config |
|------|--------|
| Disable config autosort entirely | `exclude: [:autosort]` |
| Keep autosort but skip maps inside Ecto queries | `exclude: [:autosort_ecto]` |

`# quokka:sort` always runs and is not affected by `exclude: [:autosort]`. See [Comment Directives](comment_directives.md).

## When autosort runs

For each sortable entity (map, `defstruct`, or schema block), config autosort **sorts** unless one of these applies:

1. **`# quokka:skip-sort`** on the line above the entity — opt out of autosort for that value only.
2. **The entity contains comments** — a comment in a map, `defstruct`, or schema block typically heads a human-meaningful section. Sorting the entries alphabetically scatters the section, so config autosort leaves any commented entity untouched. To sort a commented entity, use `# quokka:sort` on the line above it.
3. **Ecto query context** (when `exclude: [:autosort_ecto]` is set) — maps inside detected `from` queries are not sorted. See [Ecto queries](#ecto-queries) below.

## Comments

Config autosort skips any entity containing comments (rule 2 above). For values you do want sorted in spite of comments, opt in per-value with [`# quokka:sort`](comment_directives.md), which still sorts and attaches comments to the entry they belong to:

- A comment on the same lines as an entry, or on the line(s) immediately above it, belongs to that entry.
- After sorting, comments are placed on lines above the entry they belong to.
- End-of-line comments (for example `b: 5, # note`) are moved onto their own line above the entry, matching `mix format` behavior.

For values that autosort does not cover (plain lists, sigils, `@type` maps without autosort enabled, and so on), use [`# quokka:sort`](comment_directives.md). That directive uses the same sorting implementation and the same comment association rules.

## `# quokka:skip-sort`

Place on the line directly above a map, `defstruct`, or schema block:

```elixir
# quokka:skip-sort
%{c: 3, b: 2, a: 1}
```

## Map examples

When `autosort: [:map]` is enabled:

```elixir
# quokka:skip-sort
%{c: 3, b: 2, a: 1}

%{c: 3, b: 2, a: 1}

%{
  c: 3,
  a: 1,
  # this is a weird case
  # and the comment is multiline
  b: 2
}
```

would yield

```elixir
# quokka:skip-sort
%{c: 3, b: 2, a: 1}

%{a: 1, b: 2, c: 3}

%{
  c: 3,
  a: 1,
  # this is a weird case
  # and the comment is multiline
  b: 2
}
```

The plain map is sorted. The `# quokka:skip-sort` map is left unchanged. The commented map is left unchanged because config autosort skips any entity containing comments (see [When autosort runs](#when-autosort-runs)). To sort a commented value explicitly, use [`# quokka:sort`](comment_directives.md).

## Defstruct examples

When `autosort: [:defstruct]` is enabled, keyword and atom-list forms are sorted:

```elixir
defstruct c: 1, b: 2, a: 3
defstruct [:c, :b, :a]
```

would yield:

```elixir
defstruct a: 3, b: 2, c: 1
defstruct [:a, :b, :c]
```

## Schema examples

When `autosort: [:schema]` is enabled:

```elixir
defmodule MySchema do
  use Ecto.Schema

  schema "my_schema" do
    field :name, :string
    field :age, :integer
    field :email, :string
    has_many :posts, Post
    has_one :profile, Profile
    belongs_to :user, User
    many_to_many :tags, Tag, join_through: "my_schema_tags"
  end
end
```

would yield

```elixir
defmodule MySchema do
  use Ecto.Schema

  schema "my_schema" do
    belongs_to(:user, User)

    has_many(:posts, Post)

    has_one(:profile, Profile)

    many_to_many(:tags, Tag, join_through: "my_schema_tags")

    field(:age, :integer)
    field(:email, :string)
    field(:name, :string)
  end
end
```

## Ecto queries

Sorting within Ecto queries can be disabled with `exclude: [:autosort_ecto]`. This is useful if you use `union`, which matches on position rather than name.

Quokka uses pattern matching to identify Ecto queries and skip autosorting maps within:

- Remote calls to `Ecto.Query.from(...)`
- Local `from` macro calls that include an `in` clause (e.g., `from u in "users", ...`)

Non-Ecto functions named `from` are not affected.

When `exclude: [:autosort_ecto]` is set, the following maps are not sorted:

```elixir
# Using imported from macro (detected by 'in' clause)
query1 =
  from u in "users",
    select: %{
      id: u.id,
      name: u.name,
      email: u.email,
      active: true,
      role: "user"
    }

# Using fully qualified Ecto.Query.from
query2 =
  Ecto.Query.from(p in Post,
    select: %{
      title: p.title,
      author: p.author,
      date: p.inserted_at
    }
  )

# But non-Ecto functions named 'from' will still have their maps sorted
result = MyModule.from(%{z: 1, a: 2, m: 3})  # map will be sorted to %{a: 2, m: 3, z: 1}
```

## Related

- [`# quokka:sort`](comment_directives.md) — opt-in sorting for lists, maps, and other values (works with or without autosort enabled)
- [Module directive skip comments](module_directives.md#comment-directives) — unrelated to autosort; controls `use` / `alias` / `import` transforms
