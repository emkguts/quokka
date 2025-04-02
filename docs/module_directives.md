## Skipping Module Reordering

If you want to skip module reordering, you can add the following comment to the top of the file:

```elixir
# quokka:skip-module-reordering
```

This will prevent Quokka from doing any of the below transformations.

## Directive Expansion

This addresses:

- [`Credo.Check.Consistency.MultiAliasImportRequireUse`](https://hexdocs.pm/credo/Credo.Check.Consistency.MultiAliasImportRequireUse.html). Note that while Credo will pass as long as multi alias usage is consistent, Quokka will only expand multi-alias statements. It will not compress multiple aliases into a single statement.
- [`Credo.Check.Readability.MultiAlias`](https://hexdocs.pm/credo/Credo.Check.Readability.MultiAlias.html). Note that this is configurable and Quokka will check the Credo config to determine if aliases should be expanded.
- [`Credo.Check.Readability.UnnecessaryAliasExpansion`](https://hexdocs.pm/credo/Credo.Check.Readability.UnnecessaryAliasExpansion.html). This is not configurable.

Expands `Module.{SubmoduleA, SubmoduleB}` to their explicit forms for ease of searching.

```elixir
# Before
import Foo.{Bar, Baz, Bop}
alias Foo.{Bar, Baz.A, Bop}

# After
import Foo.Bar
import Foo.Baz
import Foo.Bop

alias Foo.Bar
alias Foo.Baz.A
alias Foo.Bop
```

## Directive Organization

This addresses:
- [`Credo.Check.Readability.AliasOrder`](https://hexdocs.pm/credo/Credo.Check.Readability.AliasOrder.html). While it is not possible to disable this rewrite, Quokka will respect the `:sort_method` Credo config.
- [`Credo.Check.Readability.StrictModuleLayout`](https://hexdocs.pm/credo/Credo.Check.Readability.StrictModuleLayout.html). While it is not possible to disable this rewrite, Quokka will respect the `:order` Credo config.

Modules directives are sorted into the following order by default:

* `@shortdoc`
* `@moduledoc`
* `@behaviour`
* `use`
* `import` (sorted alphabetically)
* `alias` (sorted alphabetically)
* `require` (sorted alphabetically)
* everything else (order unchanged)

### Before

```elixir
defmodule Foo do
  @behaviour Lawful
  alias A.A
  require A

  use B

  def c(x), do: y

  import C
  @behaviour Chaotic
  @doc "d doc"
  def d do
    alias X.X
    alias H.H

    alias Z.Z
    import Ecto.Query
    X.foo()
  end
  @shortdoc "it's pretty short"
  import A
  alias C.C
  alias D.D

  require C
  require B

  use A

  alias C.C
  alias A.A

  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)
end
```

### After

```elixir
defmodule Foo do
  @shortdoc "it's pretty short"
  @moduledoc "README.md"
             |> File.read!()
             |> String.split("<!-- MDOC !-->")
             |> Enum.fetch!(1)
  @behaviour Chaotic
  @behaviour Lawful

  use B
  use A.A

  import A.A
  import C

  alias A.A
  alias C.C
  alias D.D

  require A
  require B
  require C

  def c(x), do: y

  @doc "d doc"
  def d do
    import Ecto.Query

    alias H.H
    alias X.X
    alias Z.Z

    X.foo()
  end
end
```

If any line previously relied on an alias, the alias is fully expanded when it is moved above the alias:

```elixir
# Given
alias Foo.Bar
import Bar
# Styled
import Foo.Bar

alias Foo.Bar
```

## Alias Lifting

This addresses [`Credo.Check.Design.AliasUsage`](https://hexdocs.pm/credo/Credo.Check.Design.AliasUsage.html). The Credo configs supported by Quokka include:

- `:excluded_namespaces`
- `:excluded_lastnames`
- `:if_nested_deeper_than`
- `:if_called_more_often_than`

When a module with greater than `:if_nested_deeper_than` nested parts is referenced more than `:if_called_more_often_than` times, Quokka creates a new alias for that module and uses it.

```elixir
# Given
require A.B.C

A.B.C.foo()
A.B.C.bar()

# Styled
alias A.B.C

require C

C.foo()
C.bar()
```

### Collisions

Quokka won't lift aliases that will collide with existing aliases, and likewise won't lift any module whose name would collide with a standard library name.
