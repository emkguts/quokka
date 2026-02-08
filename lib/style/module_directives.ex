# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.ModuleDirectives do
  @moduledoc """
  Styles up module directives!

  This Style will expand multi-aliases/requires/imports/use and sort the directive within its groups (except `use`s, which cannot be sorted)
  It also adds a blank line after each directive group.

  ## Credo rules

  Rewrites for the following Credo rules:

    * `Credo.Check.Consistency.MultiAliasImportRequireUse` (force expansion)
    * `Credo.Check.Readability.AliasOrder` (we sort `__MODULE__`, which credo doesn't)
    * `Credo.Check.Readability.MultiAlias`
    * `Credo.Check.Readability.StrictModuleLayout` (see section below for details)
    * `Credo.Check.Readability.UnnecessaryAliasExpansion`
    * `Credo.Check.Design.AliasUsage`

  ### Strict Layout

  Modules directives are sorted into the following order:

    * `@shortdoc`
    * `@moduledoc`
    * `@behaviour`
    * `use`
    * `import`
    * `alias`
    * `require`
    * everything else (unchanged)
  """
  @behaviour Quokka.Style

  alias Quokka.AliasEnv
  alias Quokka.Style
  alias Quokka.Zipper

  require Logger

  @directives ~w(alias import require use)a
  @attr_directives ~w(moduledoc shortdoc behaviour)a
  @defstruct ~w(schema embedded_schema defstruct)a

  @module_placeholder "Xk9pLm3Qw7_RAND_PLACEHOLDER"
  @moduledoc_false {:@, [line: nil],
                    [
                      {:moduledoc, [line: nil], [{:__block__, [line: nil], [@module_placeholder]}]}
                    ]}

  def run({{:defmodule, _, children}, _} = zipper, ctx) do
    if has_skip_comment?(ctx) do
      {:skip, zipper, ctx}
    else
      [name, [{{:__block__, do_meta, [:do]}, _body}]] = children

      if do_meta[:format] == :keyword do
        {:skip, zipper, ctx}
      else
        moduledoc = moduledoc(name)
        # Move the zipper's focus to the module's body
        body_zipper =
          zipper
          |> Zipper.down()
          |> Zipper.right()
          |> Zipper.down()
          |> Zipper.down()
          |> Zipper.right()

        case Zipper.node(body_zipper) do
          # an empty body - replace it with a moduledoc and call it a day ¯\_(ツ)_/¯
          {:__block__, _, []} ->
            zipper = if moduledoc, do: Zipper.replace(body_zipper, moduledoc), else: body_zipper
            {:skip, zipper, ctx}

          # we want only-child literal block to be handled in the only-child catch-all. it means someone did a weird
          # (that would be a literal, so best case someone wrote a string and forgot to put `@moduledoc` before it)
          {:__block__, _, [_, _ | _]} ->
            {:skip, organize_directives(body_zipper, moduledoc, ctx), ctx}

          # a module whose only child is a moduledoc. nothing to do here!
          # seems weird at first blush but lots of projects/libraries do this with their root namespace module
          {:@, _, [{:moduledoc, _, _}]} ->
            {:skip, zipper, ctx}

          # There's only one child, and it's not a moduledoc. Conditionally add a moduledoc, then style the only_child
          only_child ->
            if moduledoc do
              zipper =
                body_zipper
                |> Zipper.replace({:__block__, [], [moduledoc, only_child]})
                |> organize_directives(nil, ctx)

              {:skip, zipper, ctx}
            else
              run(body_zipper, ctx)
            end
        end
      end
    end
  end

  # Style directives inside of snippets or function defs.
  def run({{directive, _, children}, _} = zipper, ctx) when directive in @directives and is_list(children) do
    # Need to be careful that we aren't getting false positives on variables or fns like `def import(foo)` or `alias = 1`
    case Style.ensure_block_parent(zipper) do
      {:ok, zipper} -> {:skip, zipper |> Zipper.up() |> organize_directives(nil, ctx), ctx}
      # not actually a directive! carry on.
      :error -> {:cont, zipper, ctx}
    end
  end

  # puts `@derive` before `defstruct` etc, fixing compiler warnings
  def run({{:@, _, [{:derive, _, _}]}, _} = zipper, ctx) do
    case Style.ensure_block_parent(zipper) do
      {:ok, {derive, %{l: left_siblings} = z_meta}} ->
        previous_defstruct =
          left_siblings
          |> Stream.with_index()
          |> Enum.find_value(fn
            {{struct_def, meta, _}, index} when struct_def in @defstruct -> {meta[:line], index}
            _ -> nil
          end)

        if previous_defstruct do
          {defstruct_line, defstruct_index} = previous_defstruct
          derive = Style.set_line(derive, defstruct_line - 1)
          left_siblings = List.insert_at(left_siblings, defstruct_index + 1, derive)
          {:skip, Zipper.remove({derive, %{z_meta | l: left_siblings}}), ctx}
        else
          {:cont, zipper, ctx}
        end

      :error ->
        {:cont, zipper, ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  def moduledoc_placeholder(), do: @module_placeholder

  defp moduledoc({:__aliases__, m, aliases}) do
    name = aliases |> List.last() |> to_string()
    # module names ending with these suffixes will not have a default moduledoc appended
    if !String.ends_with?(
         name,
         ~w(Test Mixfile MixProject Controller Endpoint Repo Router Socket View HTML JSON)
       ) do
      Style.set_line(@moduledoc_false, m[:line] + 1)
    end
  end

  # a dynamic module name, like `defmodule my_variable do ... end`
  defp moduledoc(_), do: nil

  @acc %{
    shortdoc: [],
    moduledoc: [],
    behaviour: [],
    use: [],
    import: [],
    alias: [],
    require: [],
    nondirectives: [],
    dealiases: %{},
    attrs: MapSet.new(),
    attr_lifts: []
  }

  defp lift_module_attrs({node, _, _} = ast, %{attrs: attrs} = acc) do
    if Enum.empty?(attrs) do
      {ast, acc}
    else
      use? = node == :use

      Macro.prewalk(ast, acc, fn
        {:@, m, [{attr, _, _} = var]} = ast, acc ->
          if attr in attrs do
            replacement =
              if use?,
                do: {:unquote, [closing: [line: m[:line]], line: m[:line]], [var]},
                else: var

            {replacement, %{acc | attr_lifts: [attr | acc.attr_lifts]}}
          else
            {ast, acc}
          end

        ast, acc ->
          {ast, acc}
      end)
    end
  end

  defp organize_directives(parent, moduledoc, ctx) do
    skip_sorting? = has_skip_directive_sorting_comment?(ctx)

    if skip_sorting? do
      organize_directives_preserve_order(parent, moduledoc)
    else
      organize_directives_with_sorting(parent, moduledoc)
    end
  end

  defp organize_directives_preserve_order(parent, moduledoc) do
    # Use zipper to traverse and expand in place, preserving structure
    parent =
      parent
      |> Zipper.traverse(fn
        {{:@, _, [{:moduledoc, _, _}]}, _} = zipper ->
          zipper

        {{directive, _, _}, _} = zipper when directive in @directives ->
          if Quokka.Config.rewrite_multi_alias?() do
            # Expand multi-aliases in place
            node = Zipper.node(zipper)
            expanded = expand(node)

            case expanded do
              [single] ->
                Zipper.replace(zipper, single)

              [first | rest] ->
                # Replace current node with first, then insert siblings after it
                zipper
                |> Zipper.replace(first)
                |> Zipper.insert_siblings(rest)

              [] ->
                Zipper.remove(zipper)
            end
          else
            zipper
          end

        zipper ->
          zipper
      end)

    # Apply alias lifting if enabled
    parent =
      if Quokka.Config.lift_alias?() do
        children = Zipper.children(parent)

        # Build dealias map from existing aliases
        existing_aliases = Enum.filter(children, &match?({:alias, _, _}, &1))
        dealiases = AliasEnv.define(existing_aliases)

        # Find liftable aliases from non-alias content
        non_alias_content = Enum.reject(children, &match?({:alias, _, _}, &1))
        liftable = find_liftable_aliases(non_alias_content, dealiases)

        if Enum.any?(liftable) do
          # Create new alias nodes
          m = [line: 999_999]

          new_aliases =
            Enum.map(liftable, fn aliases ->
              AliasEnv.expand(dealiases, {:alias, m, [{:__aliases__, [{:last, m} | m], aliases}]})
            end)

          # Transform children to use lifted aliases
          transformed_children =
            children
            |> Enum.map(fn child ->
              case child do
                {:alias, _, _} -> child
                other -> do_lift_aliases([other], liftable) |> List.first()
              end
            end)

          # Find insertion point: after last alias, or at end of directives
          {insertion_index, line_hint, after_alias?} =
            transformed_children
            |> Enum.with_index()
            |> Enum.reverse()
            |> Enum.reduce_while({nil, nil, false}, fn
              {{:alias, meta, _}, idx}, _acc ->
                {:halt, {idx + 1, meta[:line], true}}

              {{dir, meta, _}, idx}, {nil, nil, false} when dir in @directives or dir == :@ ->
                {:cont, {idx + 1, meta[:line], false}}

              _, acc ->
                {:cont, acc}
            end)

          # Insert lifted aliases at the found position
          {before_insertion, after_insertion} =
            if insertion_index do
              Enum.split(transformed_children, insertion_index)
            else
              {transformed_children, []}
            end

          # If inserting after an alias, remove end_of_expression from the preceding alias
          before_insertion =
            if after_alias? and not Enum.empty?(before_insertion) do
              {dir, meta, args} = List.last(before_insertion)
              most = Enum.drop(before_insertion, -1)
              most ++ [{dir, Keyword.delete(meta, :end_of_expression), args}]
            else
              before_insertion
            end

          # Adjust line numbers and blank lines for new aliases
          new_aliases =
            if line_hint do
              new_aliases
              |> Enum.map(&Style.set_line(&1, line_hint))
              |> then(fn aliases ->
                # Add blank line after the last lifted alias
                case List.last(aliases) do
                  nil ->
                    aliases

                  {dir, meta, args} ->
                    most = Enum.drop(aliases, -1)
                    most ++ [{dir, Keyword.put(meta, :end_of_expression, newlines: 2), args}]
                end
              end)
            else
              new_aliases
            end

          new_children = before_insertion ++ new_aliases ++ after_insertion

          Zipper.replace_children(parent, new_children)
        else
          parent
        end
      else
        parent
      end

    # Add moduledoc if needed and not present
    if moduledoc do
      children = Zipper.children(parent)
      has_moduledoc = Enum.any?(children, &match?({:@, _, [{:moduledoc, _, _}]}, &1))

      if has_moduledoc do
        parent
      else
        parent
        |> Zipper.down()
        |> Zipper.insert_left(moduledoc)
        |> Zipper.up()
      end
    else
      parent
    end
  end

  defp organize_directives_with_sorting(parent, moduledoc) do
    {before, _after} = Enum.split_while(Quokka.Config.strict_module_layout_order(), &(&1 != :alias))

    acc =
      parent
      |> Zipper.children()
      |> Enum.reduce(@acc, fn
        {:@, _, [{attr_directive, _, _}]} = ast, acc when attr_directive in @attr_directives ->
          # attr_directives might get hoisted above aliases, so need to dealias depending on the layout order
          if Enum.member?(before, attr_directive) do
            {ast, acc} = acc.dealiases |> AliasEnv.expand(ast) |> lift_module_attrs(acc)
            %{acc | attr_directive => [ast | acc[attr_directive]]}
          else
            %{acc | attr_directive => [ast | acc[attr_directive]]}
          end

        {:@, _, [{attr, _, _}]} = ast, acc ->
          %{acc | nondirectives: [ast | acc.nondirectives], attrs: MapSet.put(acc.attrs, attr)}

        {directive, _, _} = ast, acc when directive in @directives ->
          {ast, acc} = lift_module_attrs(ast, acc)

          ast =
            if Quokka.Config.rewrite_multi_alias?() do
              expand(ast)
            else
              [sort_multi_children(ast)]
            end

          # import and use might get hoisted above aliases, so need to dealias depending on the layout order
          needs_dealiasing = directive in ~w(import use)a and Enum.member?(before, directive)

          ast = if needs_dealiasing, do: AliasEnv.expand(acc.dealiases, ast), else: ast

          dealiases =
            if directive == :alias, do: AliasEnv.define(acc.dealiases, ast), else: acc.dealiases

          # the reverse accounts for `expand` putting things in reading order, whereas we're accumulating in reverse
          %{acc | directive => Enum.reverse(ast, acc[directive]), dealiases: dealiases}

        ast, acc ->
          %{acc | nondirectives: [ast | acc.nondirectives]}
      end)

    # Reversing once we're done accumulating since `reduce`ing into list accs means you're reversed!
    acc =
      acc
      |> Map.new(fn
        {:moduledoc, []} ->
          {:moduledoc, List.wrap(moduledoc)}

        {:use, uses} ->
          {:use, uses |> Enum.reverse() |> Style.reset_newlines()}

        {directive, to_sort} when directive in ~w(behaviour import alias require)a ->
          {directive, sort(to_sort, false)}

        {:dealiases, d} ->
          {:dealiases, d}

        {k, v} ->
          {k, Enum.reverse(v)}
      end)
      |> lift_aliases()

    # Not happy with it, but this does the work to move module attribute assignments above the module or quote or whatever
    # Given that it'll only be run once and not again, i'm okay with it being inefficient
    {acc, parent} =
      if Enum.any?(acc.attr_lifts) do
        lifts = acc.attr_lifts

        nondirectives =
          Enum.map(acc.nondirectives, fn
            {:@, m, [{attr, am, _}]} = ast ->
              if attr in lifts, do: {:@, m, [{attr, am, [{attr, am, nil}]}]}, else: ast

            ast ->
              ast
          end)

        assignments =
          Enum.flat_map(acc.nondirectives, fn
            {:@, m, [{attr, am, [val]}]} ->
              if attr in lifts, do: [{:=, m, [{attr, am, nil}, val]}], else: []

            _ ->
              []
          end)

        {past, _} = parent

        parent =
          parent
          |> Zipper.up()
          |> Style.find_nearest_block()
          |> Zipper.prepend_siblings(assignments)
          |> Zipper.find(&(&1 == past))

        {%{acc | nondirectives: nondirectives}, parent}
      else
        {acc, parent}
      end

    nondirectives = acc.nondirectives

    directives =
      Quokka.Config.strict_module_layout_order()
      |> Enum.map(&Map.get(acc, &1, []))
      |> Stream.concat()
      |> fix_line_numbers(List.first(nondirectives))

    # the # of aliases can be decreased during sorting - if there were any, we need to be sure to write the deletion
    if Enum.empty?(directives) do
      Zipper.replace_children(parent, nondirectives)
    else
      # this ensures we continue the traversal _after_ any directives
      parent
      |> Zipper.replace_children(directives)
      |> Zipper.down()
      |> Zipper.rightmost()
      |> Zipper.insert_siblings(nondirectives)
    end
  end

  defp lift_aliases(%{alias: aliases, nondirectives: nondirectives} = acc) do
    # we can't use the dealias map built into state as that's what things look like before sorting
    # now that we've sorted, it could be different!
    dealiases = AliasEnv.define(aliases)

    {_before, [_alias | after_alias]} =
      Quokka.Config.strict_module_layout_order()
      |> Enum.split_while(&(&1 != :alias))

    liftable =
      if Quokka.Config.lift_alias?() do
        Map.take(acc, after_alias)
        |> Map.values()
        |> List.flatten()
        |> Kernel.++(nondirectives)
        |> find_liftable_aliases(dealiases)
      else
        []
      end

    if Enum.any?(liftable) do
      # This is a silly hack that helps comments stay put.
      # The `cap_line` algo was designed to handle high-line stuff moving up into low line territory, so we set our
      # new node to have an arbitrarily high line annnnd comments behave! i think.
      m = [line: 999_999]

      aliases =
        liftable
        |> Enum.map(&AliasEnv.expand(dealiases, {:alias, m, [{:__aliases__, [{:last, m} | m], &1}]}))
        |> Enum.concat(aliases)
        |> sort(false)

      lifted_directives =
        Map.take(acc, after_alias)
        |> Map.new(fn
          {:behaviour, ast_nodes} -> {:behaviour, ast_nodes}
          {:use, ast_nodes} -> {:use, do_lift_aliases(ast_nodes, liftable)}
          {directive, ast_nodes} -> {directive, ast_nodes |> do_lift_aliases(liftable) |> sort(false)}
        end)

      nondirectives = do_lift_aliases(nondirectives, liftable)

      Map.merge(acc, lifted_directives)
      |> Map.merge(%{nondirectives: nondirectives, alias: aliases})
    else
      acc
    end
  end

  defp find_liftable_aliases(ast, dealiases) do
    excluded = dealiases |> Map.keys() |> Enum.into(Quokka.Config.lift_alias_excluded_lastnames())

    firsts = MapSet.new(dealiases, fn {_last, [first | _]} -> first end)

    ast
    |> Zipper.zip()
    # we're reducing a datastructure that looks like
    # %{last => {aliases, seen_before?} | :some_collision_probelm}
    |> Zipper.reduce_while(%{}, fn
      # we don't want to rewrite alias name `defx Aliases ... do` of these three keywords
      {{defx, _, args}, _} = zipper, lifts when defx in ~w(defmodule defimpl defprotocol)a ->
        # don't conflict with submodules, which elixir automatically aliases
        # we could've done this earlier when building excludes from aliases, but this gets it done without two traversals.
        lifts =
          case args do
            [{:__aliases__, _, aliases} | _] when defx == :defmodule ->
              Map.put(lifts, List.last(aliases), :collision_with_submodule)

            _ ->
              lifts
          end

        # move the focus to the body block, zkipping over the alias (and the `for` keyword for `defimpl`)
        {:skip, zipper |> Zipper.down() |> Zipper.rightmost() |> Zipper.down() |> Zipper.down(), lifts}

      {{:quote, _, _}, _} = zipper, lifts ->
        {:skip, zipper, lifts}

      {{:__aliases__, _, [first, _ | _] = aliases}, _} = zipper, lifts ->
        if Enum.all?(aliases, &is_atom/1) do
          alias_string = Enum.join(aliases, ".")

          included_namespace? =
            case Quokka.Config.lift_alias_only() do
              nil ->
                true

              only ->
                only
                |> List.wrap()
                |> Enum.any?(&Regex.match?(&1, alias_string))
            end

          excluded_namespace? =
            Quokka.Config.lift_alias_excluded_namespaces()
            |> MapSet.filter(fn namespace ->
              String.starts_with?(alias_string, Atom.to_string(namespace) <> ".")
            end)
            |> MapSet.size() > 0

          last = List.last(aliases)

          lifts =
            cond do
              # this alias existed before running format, so let's ensure it gets lifted
              dealiases[last] == aliases ->
                Map.put(lifts, last, {aliases, Quokka.Config.lift_alias_frequency() + 1})

              # this alias would conflict with an existing alias, or the namespace is excluded, or the depth is too shallow
              last in excluded or excluded_namespace? or length(aliases) <= Quokka.Config.lift_alias_depth() ->
                lifts

              # aliasing this would change the meaning of an existing alias
              last > first and last in firsts ->
                lifts

              # if only is set, don't lift aliases that don't match the only regex
              not included_namespace? ->
                lifts

              # Never seen this alias before
              is_nil(lifts[last]) ->
                Map.put(lifts, last, {aliases, 1})

              # We've seen this before, add and do some bookkeeping for first-collisions
              match?({^aliases, n} when is_integer(n), lifts[last]) ->
                Map.put(lifts, last, {aliases, elem(lifts[last], 1) + 1})

              # There is some type of collision
              true ->
                lifts
            end

          {:skip, zipper, Map.put(lifts, first, :collision_with_first)}
        else
          {:skip, zipper, lifts}
        end

      {{directive, _, [{:__aliases__, _, _} | _]}, _} = zipper, lifts when directive in [:use, :import, :behaviour] ->
        {:cont, zipper |> Zipper.down() |> Zipper.rightmost(), lifts}

      zipper, lifts ->
        {:cont, zipper, lifts}
    end)
    |> Enum.filter(fn {_last, value} ->
      case value do
        {_aliases, count} -> count > Quokka.Config.lift_alias_frequency()
        _ -> false
      end
    end)
    |> MapSet.new(fn {_, {aliases, _count}} -> aliases end)
  end

  defp do_lift_aliases(ast, to_alias) do
    ast
    |> Zipper.zip()
    |> Zipper.traverse(fn
      {{defx, _, [{:__aliases__, _, _} | _]}, _} = zipper
      when defx in ~w(defmodule defimpl defprotocol)a ->
        # move the focus to the body block, zkipping over the alias (and the `for` keyword for `defimpl`)
        zipper
        |> Zipper.down()
        |> Zipper.rightmost()
        |> Zipper.down()
        |> Zipper.down()
        |> Zipper.right()

      {{:alias, _, [{:__aliases__, _, [_, _ | _] = aliases}]}, _} = zipper ->
        # the alias was aliased deeper down. we've lifted that alias to a root, so delete this alias
        if aliases in to_alias and Enum.all?(aliases, &is_atom/1) and
             length(aliases) > Quokka.Config.lift_alias_depth(),
           do: Zipper.remove(zipper),
           else: zipper

      {{:__aliases__, meta, [_, _ | _] = aliases}, _} = zipper ->
        if aliases in to_alias and Enum.all?(aliases, &is_atom/1) and
             length(aliases) > Quokka.Config.lift_alias_depth(),
           do: Zipper.replace(zipper, {:__aliases__, meta, [List.last(aliases)]}),
           else: zipper

      zipper ->
        zipper
    end)
    |> Zipper.node()
  end

  # Deletes root level aliases ala (`alias Foo` -> ``)
  defp expand({:alias, _, [{:__aliases__, _, [_]}]}), do: []

  # import Foo.{Bar, Baz}
  # =>
  # import Foo.Bar
  # import Foo.Baz
  defp expand({directive, meta, [{{:., _, [{:__aliases__, _, module}, :{}]}, _, right}]}) do
    expanded =
      Enum.map(right, fn {_, child_meta, segments} ->
        {directive, child_meta, [{:__aliases__, [line: child_meta[:line]], module ++ segments}]}
      end)

    # Preserve the end_of_expression metadata from the original node on the last expanded node
    case expanded do
      [] ->
        []

      [single] ->
        {dir, child_meta, args} = single
        [{dir, Keyword.merge(child_meta, Keyword.take(meta, [:end_of_expression])), args}]

      list ->
        {last_dir, last_meta, last_args} = List.last(list)
        most = Enum.drop(list, -1)
        most ++ [{last_dir, Keyword.merge(last_meta, Keyword.take(meta, [:end_of_expression])), last_args}]
    end
  end

  # alias __MODULE__.{Bar, Baz}
  defp expand({directive, meta, [{{:., _, [{:__MODULE__, _, _} = module, :{}]}, _, right}]}) do
    expanded =
      Enum.map(right, fn {_, child_meta, segments} ->
        {directive, child_meta, [{:__aliases__, [line: child_meta[:line]], [module | segments]}]}
      end)

    # Preserve the end_of_expression metadata from the original node on the last expanded node
    case expanded do
      [] ->
        []

      [single] ->
        {dir, child_meta, args} = single
        [{dir, Keyword.merge(child_meta, Keyword.take(meta, [:end_of_expression])), args}]

      list ->
        {last_dir, last_meta, last_args} = List.last(list)
        most = Enum.drop(list, -1)
        most ++ [{last_dir, Keyword.merge(last_meta, Keyword.take(meta, [:end_of_expression])), last_args}]
    end
  end

  defp expand(other), do: [other]

  # When multi directives are not expanded, maintain brace form but sort inner items
  defp sort_multi_children({directive, dm, [{{:., m, [{left_type, _, _} = left, :{}]}, meta, right}]})
       when directive in @directives and left_type in [:__aliases__, :__MODULE__] do
    {directive, dm, [{{:., m, [left, :{}]}, meta, sort_terms(right)}]}
  end

  defp sort_multi_children(other), do: other

  defp sort(directives, skip_sorting?) do
    directives
    |> then(fn dirs ->
      if skip_sorting? do
        # When skipping sorting, we still need to reverse since we accumulated in reverse order
        Enum.reverse(dirs)
      else
        sort_terms(dirs)
      end
    end)
    |> Style.reset_newlines()
  end

  defp sort_terms(asts) do
    sort_method = Quokka.Config.sort_order()

    asts
    |> Enum.map(fn ast ->
      key = get_sort_key(ast, sort_method)
      tie = Macro.to_string(ast)
      tie = if sort_method == :ascii, do: tie, else: String.downcase(tie)
      {ast, key, tie}
    end)
    |> Enum.uniq_by(fn {_, key, tie} -> {key, tie} end)
    |> Enum.sort_by(fn {_, key, tie} -> {key, tie} end)
    |> Enum.map(&elem(&1, 0))
  end

  # Get the sort key for an alias, using first child's full path for multi-aliases
  # This ensures compatibility with Credo.Check.Readability.AliasOrder which compares
  # the first expanded child module path, not just the parent module.
  defp get_sort_key({:alias, _, [{{:., _, [{:__aliases__, _, mod_list}, :{}]}, _, children}]}, sort_method) do
    # Multi-alias: use alias parent.first_alphabetical_child as sort key
    parent = Enum.map_join(mod_list, ".", &to_string/1)

    # Sort children to get the alphabetically first one
    first_child =
      children
      |> Enum.map(fn {:__aliases__, _, parts} ->
        {Enum.map_join(parts, ".", &to_string/1), parts}
      end)
      |> Enum.sort_by(fn {str, _} ->
        if sort_method == :ascii, do: str, else: String.downcase(str)
      end)
      |> List.first()
      |> elem(1)
      |> Enum.map_join(".", &to_string/1)

    full_path = "alias #{parent}.#{first_child}"
    if sort_method == :ascii, do: full_path, else: String.downcase(full_path)
  end

  defp get_sort_key({:alias, _, [{{:., _, [{:__MODULE__, _, _}, :{}]}, _, children}]}, sort_method) do
    # Multi-alias with __MODULE__: use alias __MODULE__.first_alphabetical_child as sort key

    # Sort children to get the alphabetically first one
    first_child =
      children
      |> Enum.map(fn {:__aliases__, _, parts} ->
        {Enum.map_join(parts, ".", &to_string/1), parts}
      end)
      |> Enum.sort_by(fn {str, _} ->
        if sort_method == :ascii, do: str, else: String.downcase(str)
      end)
      |> List.first()
      |> elem(1)
      |> Enum.map_join(".", &to_string/1)

    full_path = "alias __MODULE__.#{first_child}"
    if sort_method == :ascii, do: full_path, else: String.downcase(full_path)
  end

  defp get_sort_key(directive, sort_method) do
    # Single alias or other directive: use macro string representation
    str = Macro.to_string(directive)
    if sort_method == :ascii, do: str, else: String.downcase(str)
  end

  defp has_skip_comment?(context) do
    skip_module_directives = Enum.any?(context.comments, &String.contains?(&1.text, "quokka:skip-module-directives"))
    skip_module_reordering = Enum.any?(context.comments, &String.contains?(&1.text, "quokka:skip-module-reordering"))

    if skip_module_reordering do
      Logger.warning("skip-module-reordering is deprecated in favor of skip-module-directives")
    end

    skip_module_directives or skip_module_reordering
  end

  defp has_skip_directive_sorting_comment?(context) do
    Enum.any?(
      context.comments,
      &String.contains?(&1.text, "quokka:skip-module-directive-reordering")
    )
  end

  # TODO investigate removing this in favor of the Style.post_sort_cleanup(node, comments)
  # "Fixes" the line numbers of nodes who have had their orders changed via sorting or other methods.
  # This "fix" simply ensures that comments don't get wrecked as part of us moving AST nodes willy-nilly.
  #
  # The fix is rather naive, and simply enforces the following property on the code:
  # A given node must have a line number less than the following node.
  # Et voila! Comments behave much better.
  #
  # ## In Detail
  #
  # For example, given document
  #
  #   1: defmodule ...
  #   2: alias B
  #   3: # this is foo
  #   4: def foo ...
  #   5: alias A
  #
  # Sorting aliases the ast node for  would put `alias A` (line 5) before `alias B` (line 2).
  #
  #   1: defmodule ...
  #   5: alias A
  #   2: alias B
  #   3: # this is foo
  #   4: def foo ...
  #
  # Elixir's document algebra would then encounter `line: 5` and immediately dump all comments with `line <= 5`,
  # meaning after running through the formatter we'd end up with
  #
  #   1: defmodule
  #   2: # hi
  #   3: # this is foo
  #   4: alias A
  #   5: alias B
  #   6:
  #   7: def foo ...
  #
  # This function fixes that by seeing that `alias A` has a higher line number than its following sibling `alias B` and so
  # updates `alias A`'s line to be preceding `alias B`'s line.
  #
  # Running the results of this function through the formatter now no longer dumps the comments prematurely
  #
  #   1: defmodule ...
  #   2: alias A
  #   3: alias B
  #   4: # this is foo
  #   5: def foo ...
  defp fix_line_numbers(nodes, nil), do: fix_line_numbers(nodes, 999_999)
  defp fix_line_numbers(nodes, {_, meta, _}), do: fix_line_numbers(nodes, meta[:line])
  defp fix_line_numbers(nodes, max), do: nodes |> Enum.reverse() |> do_fix_lines(max, [])

  defp do_fix_lines([], _, acc), do: acc

  defp do_fix_lines([{_, meta, _} = node | nodes], max, acc) do
    line = meta[:line]

    # the -2 is just an ugly hack to leave room for one-liner comments and not hijack them.
    if line > max,
      do: do_fix_lines(nodes, max, [Style.shift_line(node, max - line - 2) | acc]),
      else: do_fix_lines(nodes, line, [node | acc])
  end
end
