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

  def define(env, {:alias, _, [{{:., _, [{:__aliases__, _, ns}, :{}]}, _, children}]}) do
    base =
      case ns do
        [:"Elixir" | canonical] when canonical != [] -> canonical
        _ -> do_expand(env, ns)
      end

    put_multi(env, base, children)
  end

  def define(env, {:alias, _, [{:__aliases__, _, aliases} | opts]}) do
    case bound_as(aliases, opts) do
      {:ok, as} -> define(env, aliases, as)
      :dynamic -> env
    end
  end

  def define(env, _ast), do: env

  @doc """
  Records alias bindings whose paths have already been resolved against `env`, without expanding
  their leading segments a second time.
  """
  def define_resolved(env, asts) when is_list(asts), do: Enum.reduce(asts, env, &define_resolved(&2, &1))

  def define_resolved(env, {:alias, _, [{{:., _, [{:__aliases__, _, ns}, :{}]}, _, children}]}) do
    base =
      case ns do
        [:"Elixir" | canonical] when canonical != [] -> canonical
        _ -> ns
      end

    put_multi(env, base, children)
  end

  def define_resolved(env, {:alias, _, [{:__aliases__, _, modules} | opts]}) do
    case bound_as(modules, opts) do
      {:ok, as} -> put_resolved(env, modules, as)
      :dynamic -> env
    end
  end

  def define_resolved(env, _ast), do: env

  defp put_multi(env, base, children) do
    Enum.reduce(children, env, fn
      {:__aliases__, _, segs}, acc ->
        case List.last(segs) do
          as when is_atom(as) -> Map.put(acc, as, base ++ segs)
          _ -> acc
        end

      _, acc ->
        acc
    end)
  end

  @doc false
  def alias_as_opt([opts]) when is_list(opts) do
    Enum.find_value(opts, :none, fn
      {{:__block__, _, [:as]}, {:__aliases__, _, [as]}} when is_atom(as) -> {:ok, as}
      {:as, {:__aliases__, _, [as]}} when is_atom(as) -> {:ok, as}
      {{:__block__, _, [:as]}, _} -> :dynamic
      {:as, _} -> :dynamic
      _ -> nil
    end)
  end

  def alias_as_opt(_), do: :none

  defp bound_as(modules, opts) do
    case alias_as_opt(opts) do
      {:ok, as} ->
        {:ok, as}

      :dynamic ->
        :dynamic

      :none ->
        case List.last(modules) do
          as when is_atom(as) -> {:ok, as}
          _ -> :dynamic
        end
    end
  end

  defp define(env, [:"Elixir" | canonical], as) when canonical != [], do: Map.put(env, as, canonical)
  defp define(env, modules, as), do: Map.put(env, as, do_expand(env, modules))

  defp put_resolved(env, [:"Elixir" | canonical], as) when canonical != [], do: Map.put(env, as, canonical)
  defp put_resolved(env, modules, as), do: Map.put(env, as, modules)

  # no need to traverse ast if there are no aliases
  def expand(env, ast) when map_size(env) == 0, do: ast
  def expand(env, ast), do: expand_ast(env, ast)

  # Only expand the namespace to the left of `.{}` — child segments are relative to it,
  # not top-level aliases (e.g. `import Baz.{Bar, Qux}` must not expand `Bar` against `alias Foo.Bar`).
  defp expand_ast(env, {{:., dm, [{:__aliases__, nm, namespace}, :{}]}, cm, children}) do
    {{:., dm, [{:__aliases__, nm, do_expand(env, namespace)}, :{}]}, cm, children}
  end

  defp expand_ast(env, {:__aliases__, meta, modules}) do
    {:__aliases__, meta, do_expand(env, modules)}
  end

  defp expand_ast(env, {form, meta, args}) when is_list(args) do
    {expand_ast(env, form), meta, Enum.map(args, &expand_ast(env, &1))}
  end

  defp expand_ast(env, {a, b}), do: {expand_ast(env, a), expand_ast(env, b)}
  defp expand_ast(env, list) when is_list(list), do: Enum.map(list, &expand_ast(env, &1))
  defp expand_ast(_env, other), do: other

  @doc """
  Resolve just the leading module path of an `alias` directive against `env`.

  Unlike `expand/2`, this only rewrites the alias's own module path (and, for brace-multi forms,
  the namespace to the left of the `.{}`). Child segments of a `Foo.{Bar, Baz}` form are not
  aliases in their own right, so they're left untouched.
  """
  def dealias_directive(env, ast, opts \\ [])
  def dealias_directive(env, ast, _opts) when map_size(env) == 0, do: ast
  def dealias_directive(_env, {:alias, _, [{:__aliases__, _, [:"Elixir" | _]} | _]} = ast, _), do: ast

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
          # After sorting, an alias like `B.E` (or `B, as: Other`) can end up below `alias A.B`
          # even though it was written first and meant top-level `B`. Prefix with `Elixir.` to preserve that meaning.
          [:"Elixir" | modules]
        else
          expanded
        end
    end
  end

  # Single-step O(1) resolution against `env`.
  # Every entry in `env` is already canonical (resolved at the time it was defined), so we never
  # re-expand the resolved target. This matches Elixir's alias semantics, avoids O(N^2) Macro.Env
  # construction, and avoids Elixir 1.15.x's recursive lookup hang on indirect self-aliases.
  defp do_expand(_env, [:"Elixir" | _] = modules), do: modules

  defp do_expand(env, [first | rest] = modules) do
    case Map.get(env, first) do
      nil ->
        modules

      ^modules ->
        modules

      # A self-referential alias (e.g. `alias Foo.Foo`, `alias A.A.A`) resolves its own leading segment
      # back to a path that still begins with that segment. Appending a remainder would deepen the path
      # (`Foo.Bar` -> `Foo.Foo.Bar`, then again on later passes). Leave the path alone in that case.
      [^first | _] when rest != [] ->
        modules

      resolved when is_list(resolved) ->
        if Enum.all?(modules, &is_atom/1) and Enum.all?(resolved, &is_atom/1) do
          resolved ++ rest
        else
          modules
        end

      _ ->
        modules
    end
  end
end
