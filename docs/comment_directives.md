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

Quokka can autosort maps, defstructs, and schemas. To enable this feature, set `autosort: [:map, :defstruct, :schema]` in the config. The order of schema sorting can be customized in the following way:

```elixir
autosort: [:map, schema: [:field, :belongs_to]]
```

The default order is: `[:field, :belongs_to, :has_many, :has_one, :many_to_many, :embeds_many, :embeds_one]`.

Quokka will skip sorting entities that have comments inside them, though sorting can still be forced with `# quokka:sort`. Finally, when `autosort` is enabled, a specific entity can be skipped by adding `# quokka:skip-sort` on the line above it.

Sorting within Ecto queries can be disabled by specifying `exclude: [:autosort_ecto]`. If your codebase makes use of `union` queries, this option may be desirable, since `union` matches on position and not on name.

**Note on Ecto Query Detection**: Quokka uses pattern matching to identify Ecto queries and will skip autosorting maps within:
- Remote calls to `Ecto.Query.from(...)`
- Local `from` macro calls that include an `in` clause (e.g., `from u in "users", ...`)

This detection is designed to prevent false positives while catching the most common Ecto query patterns. Non-Ecto functions named `from` will not be affected.

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

would yield:

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

When `autosort: [:exclude_ecto]` is enabled, the following will not get sorted:
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
