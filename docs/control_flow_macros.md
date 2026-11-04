# Control Flow Macros (`case`, `if`, `unless`, `cond`, `with`)

Elixir's Kernel documentation refers to these structures as "macros for control-flow".
We often refer to them as "blocks" in our changelog, which is a much worse name, to be sure.

## `if` and `unless`

Quokka removes `else: nil` clauses:

```elixir
if a, do: b, else: nil
# styled:
if a, do: b
```

Quokka removes `unless` since it is being deprecated in Elixir 1.18. This implicitly addresses [`Credo.Check.Refactor.NegatedConditionsInUnless`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsInUnless.html) and [`Credo.Check.Refactor.NegatedConditionsWithElse`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsWithElse.html).

```elixir
# Given:
unless a, do: b
# Styled:
if a, do: b
```

It also removes `do: nil` when an `else` is present, inverting the head to maintain semantics

```elixir
if a, do: nil, else: b
# styled:
if !a, do: b
```

### Negation Inversion

This addresses [`Credo.Check.Refactor.NegatedConditionsWithElse`](https://hexdocs.pm/credo/Credo.Check.Refactor.NegatedConditionsWithElse.html).

This behavior can be disabled by setting the check to `false` in your `.credo.exs`:

```elixir
{Credo.Check.Refactor.NegatedConditionsWithElse, false}
```

Quokka removes negators in the head of `if` statements with an `else` clause by "inverting" the statement.
The following operators are considered "negators": `!`, `not`, `!=`, `!==`

Examples:

```elixir
# negated `if` statements with an `else` clause have their clauses inverted and negation removed
if !x, do: y, else: z
# Styled:
if x, do: z, else: y
```

### Double Negation Removal

This is always applied, regardless of the `NegatedConditionsWithElse` configuration.

Because Elixir relies on truthy/falsey values for its `if` statements, boolean casting is unnecessary and so double negation is simply removed.

```elixir
if !!x, do: y
# styled:
if x, do: y
```

## `cond`

This addresses [`Credo.Check.Refactor.CondStatements`](https://hexdocs.pm/credo/Credo.Check.Refactor.CondStatements.html).

This behavior can be disabled by disabling the check in your `.credo.exs`:

```elixir
{Credo.Check.Refactor.CondStatements, false}
```

Quokka has only one `cond` statement rewrite: replace 2-clause statements with `if` statements.

```elixir
# Given
cond do
  a -> b
  true -> c
end
# Styled
if a do
  b
else
  c
end
```

## `with`

This addresses [`Credo.Check.Readability.WithSingleClause`](https://hexdocs.pm/credo/Credo.Check.Readability.WithSingleClause.html), [`Credo.Check.Refactor.RedundantWithClauseResult`](https://hexdocs.pm/credo/Credo.Check.Refactor.RedundantWithClauseResult.html), and [`Credo.Check.Refactor.WithClauses`](https://hexdocs.pm/credo/Credo.Check.Refactor.WithClauses.html). This is not configurable.

### Remove Identity Else Clause

Like if statements with `nil` as their else clause, the identity `else` clause is the default for `with` statements and so is removed.

```elixir
# Given
with :ok <- b(), :ok <- b() do
  foo()
else
  error -> error
end
# Styled:
with :ok <- b(), :ok <- b() do
  foo()
end
```

### Remove The Statement Entirely

While you might think "surely this kind of code never appears in the wild", it absolutely does. Typically it's the result of someone refactoring a pattern away and not looking at the larger picture and realizing that the with statement now serves no purpose.

Maybe someday the compiler will warn about these use cases. Until then, Quokka to the rescue.

```elixir
# Given:
with a <- b(),
     c <- d(),
     e <- f(),
     do: g,
     else: (_ -> h)
# Styled:
a = b()
c = d()
e = f()
g

# Given
with value <- arg do
  value
end
# Styled:
arg
```

### Replace `_ <- rhs` with `rhs`

This is another case of "less is more" for the reader.

```elixir
# Given
with :ok <- x,
     _ <- y(),
     {:ok, _} <- z do
  :ok
end
# Styled:
with :ok <- x,
     y(),
     {:ok, _} <- z do
  :ok
end
```

### Replace non-branching `bar <-` with `bar =`

`<-` is for branching. If the lefthand side is the trivial match (a bare variable), Quokka rewrites it to use the `=` operator instead.

```elixir
# Given
with :ok <- foo(),
     bar <- baz(),
     :ok <- woo(),
     do: {:ok, bar}
# Styled
 with :ok <- foo(),
      bar = baz(),
      :ok <- woo(),
      do: {:ok, bar}
```

### Move assignments from `with` statement head

Just because any program _could_ be written entirely within the head of a `with` statement doesn't mean it should be!

Quokka moves assignments that aren't trapped between `<-` outside of the head. Combined with the non-pattern-matching replacement above, we get the following:

```elixir
# Given
with foo <- bar,
     x = y,
     :ok <- baz,
     bop <- boop,
     :ok <- blop,
     foo <- bar,
     :success = hope_this_works! do
  :ok
end
# Styled:
foo = bar
x = y

with :ok <- baz,
     bop = boop,
     :ok <- blop do
  foo = bar
  :success = hope_this_works!
  :ok
end
```

### Remove redundant final clause

If the pattern of the final clause of the head is also the `with` statements `do` body, quokka nixes the final match and makes the right hand side of the clause into the do body.

```elixir
# Given
with {:ok, a} <- foo(),
     {:ok, b} <- bar(a) do
  {:ok, b}
end
# Styled:
with {:ok, a} <- foo() do
  bar(a)
end
```

### Replace with `case`

A `with` statement with a single clause in the head and an `else` body is really just a `case` statement putting on airs.

```elixir
# Given:
with :ok <- foo do
  :success
else
  :fail -> :failure
  error -> error
end
# Styled:
case foo do
  :ok -> :success
  :fail -> :failure
  error -> error
end
```

Of course, Quokka must *not* rewrite `with true <- x, do: body` (lacking a catch-all `else` clause) to `if x, do: body`, since the change is not equivalent: `with true <- x` returns `x` when the match fails (including for `false` and non-boolean truthy values), while `if` treats the head as truthy/falsey and returns `nil` when the condition is false.

## Reusing Matched Terms

When a clause matches a tuple or list and then returns an identical copy of it, Quokka binds the match to a variable and returns that instead, saving a memory allocation.
This applies to clauses of `case`, `with ... else`, `fn`, `receive`, `try ... else`/`catch`, `for ... reduce:`, and `def`/`defp` heads.
The new variable is named `error` when the term is tagged with `:error`, and `result` otherwise.

```elixir
# Given:
case foo(bar) do
  {:ok, val} -> {:ok, val}
  {:error, reason} -> {:error, reason}
end
# Styled:
case foo(bar) do
  {:ok, _val} = result -> result
  {:error, _reason} = error -> error
end
```

Variables still used in guards or elsewhere in the clause keep their names:

```elixir
# Given:
def foo({:ok, val}) when is_integer(val) do
  Logger.info("hi")
  {:ok, val}
end

def foo({:ok, %User{} = user} = bar), do: {:ok, user}
# Styled:
def foo({:ok, val} = result) when is_integer(val) do
  Logger.info("hi")
  result
end

def foo({:ok, %User{}} = bar), do: bar
```

This rewrite ignores clauses that:

- rebuild maps (which may have had more keys than were matched),
- contain only literals (which aren't allocated at runtime), or
- rebind one of the matched variables before returning.
