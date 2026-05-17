# Autosort

Config-driven sorting for maps, `defstruct`s, and Ecto schemas. Enable it in `.formatter.exs`:

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

For each sortable entity (map, `defstruct`, or schema block), autosort **sorts** unless one of these applies:

1. **`# quokka:skip-sort`** on the line above the entity — opt out of autosort for that value only.
2. **Comments inside the entity** — autosort skips the entity so inline comments that document ordering are preserved. Use [`# quokka:sort`](comment_directives.md) on the line above to force sorting anyway.
3. **Ecto query context** (when `exclude: [:autosort_ecto]` is set) — maps inside detected `from` queries are not sorted. See [Ecto queries](#ecto-queries) below.

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

The plain map is sorted. The `# quokka:skip-sort` map is left unchanged. The map with an inline comment is left unchanged by autosort (see skip rule 2 above). The map under `# quokka:sort` is sorted by the [comment directive](comment_directives.md), including when comments are inside the map.

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
