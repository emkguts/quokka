defmodule Quokka.AliasEnv do
  @moduledoc """
  A datastructure for maintaining something like compiler alias state when traversing AST.

  Not anywhere as correct as what the compiler gives us, but close enough for open source work.

  A alias env is a map from an alias's `as` to its resolution in a context.

  Given the ast for

      alias Foo.Bar

  we'd create the env:

      %{:Bar => [:Foo, :Bar]}
  """
  def define(env \\ %{}, ast)

  def define(env, asts) when is_list(asts), do: Enum.reduce(asts, env, &define(&2, &1))

  def define(env, {:alias, _, aliases}) do
    case aliases do
      [{:__aliases__, _, aliases}] -> define(env, aliases, List.last(aliases))
      [{:__aliases__, _, aliases}, [{_as, {:__aliases__, _, [as]}}]] -> define(env, aliases, as)
      # `alias __MODULE__` or other oddities i'm not bothering to get right
      _ -> env
    end
  end

  defp define(env, modules, as), do: Map.put(env, as, do_expand(env, modules))

  # no need to traverse ast if there are no aliases
  def expand(env, ast) when map_size(env) == 0, do: ast

  def expand(env, ast) do
    Macro.prewalk(ast, fn
      {:__aliases__, meta, modules} -> {:__aliases__, meta, do_expand(env, modules)}
      ast -> ast
    end)
  end

  @doc """
  Resolve just the leading module path of an `alias` directive against `env`.

  Unlike `expand/2`, this only rewrites the alias's own module path (and, for brace-multi forms,
  the namespace to the left of the `.{}`). Child segments of a `Foo.{Bar, Baz}` form are not
  aliases in their own right, so they're left untouched.
  """
  def dealias_directive(env, ast, opts \\ [])
  def dealias_directive(env, ast, _opts) when map_size(env) == 0, do: ast
  def dealias_directive(_env, {:alias, m, [{:__aliases__, _, [Elixir | _]} = aliases]}, _), do: {:alias, m, [aliases]}

  def dealias_directive(env, {:alias, m, [{:__aliases__, am, modules} | rest]}, opts) do
    {:alias, m, [{:__aliases__, am, expand_alias_path(env, modules, opts)} | rest]}
  end

  def dealias_directive(env, {:alias, m, [{{:., dm, [{:__aliases__, nm, namespace}, :{}]}, cm, children}]}, opts) do
    {:alias, m, [{{:., dm, [{:__aliases__, nm, expand_alias_path(env, namespace, opts)}, :{}]}, cm, children}]}
  end

  def dealias_directive(_env, ast, _opts), do: ast

  defp expand_alias_path(env, modules, opts) do
    case do_expand(env, modules) do
      ^modules ->
        modules

      expanded ->
        if Access.get(opts, :disambiguate, false) do
          disambiguate_or_keep(modules)
        else
          expanded
        end
    end
  end

  # After sorting, an alias like `B.E` can end up below `alias A.B` even though it was written first and
  # meant top-level `B.E`. Prefix with `Elixir.` to preserve that meaning. `D.D`-style paths are left
  # alone since the repeated segment already pins the module path.
  defp disambiguate_or_keep([first | rest] = modules) when rest != [] and rest != [first], do: [:"Elixir" | modules]
  defp disambiguate_or_keep(modules), do: modules

  # if the list of modules is itself already aliased, dealias it with the compound alias
  # given:
  #   alias Foo.Bar
  #   Bar.Baz.Bop.baz()
  #
  # lifting Bar.Baz.Bop should result in:
  #   alias Foo.Bar
  #   alias Foo.Bar.Baz.Bop
  #   Bop.baz()
  defp do_expand(env, [first | rest] = modules) do
    case env[first] do
      nil ->
        modules

      # A self-referential alias (e.g. `alias Foo.Foo`, `as: Foo`) resolves its own leading segment
      # back to a path that still begins with that segment. Appending a remainder to it would deepen
      # the path without bound (`Foo.Foo.Bar` -> `Foo.Foo.Foo.Bar` -> ...) and never reach a
      # fixpoint, and it also covers a redundant duplicate of the alias itself. In those cases treat
      # the segment as top-level and leave the path alone. (Resolving the bare alias name, where
      # there's no remainder, is still fine and idempotent.)
      [^first | _] when rest != [] ->
        modules

      dealias ->
        dealias ++ rest
    end
  end
end
