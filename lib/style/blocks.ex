# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.Blocks do
  @moduledoc """
  Simple 1-1 rewrites all crammed into one module to make for more efficient traversals

  Credo Rules addressed:

  * Credo.Check.Readability.LargeNumbers
  * Credo.Check.Readability.ParenthesesOnZeroArityDefs
  * Credo.Check.Readability.WithSingleClause
  * Credo.Check.Refactor.CondStatements
  * Credo.Check.Refactor.RedundantWithClauseResult
  * Credo.Check.Refactor.WithClauses
  """

  @behaviour Quokka.Style

  alias Quokka.Config
  alias Quokka.Style
  alias Quokka.Zipper

  defguardp is_negator(n) when elem(n, 0) in [:!, :not, :!=, :!==]
  defguardp is_empty_body(n) when elem(n, 0) == :__block__ and elem(n, 2) in [[nil], []]

  # `{form, keyword}` pairs whose `->` clauses have patterns for heads (`def`/`defp` being implicit `try`s)
  # These are candidates for rewrite by `reuse_matched_term/4`
  @pattern_clause_forms [
    case: :do,
    receive: :do,
    for: :do,
    with: :else,
    try: :else,
    try: :catch,
    def: :else,
    def: :catch,
    defp: :else,
    defp: :catch
  ]

  # Pipe into case: case foo |> bar() do ... end => foo |> bar() |> case do ... end
  def run({{:case, case_meta, [{:|>, _, _} = pipe_chain, clauses]}, _} = zipper, ctx) do
    if Quokka.Config.pipe_into_case?() do
      new_node = {:|>, [line: case_meta[:line]], [pipe_chain, {:case, case_meta, [clauses]}]}
      {:cont, Zipper.replace(zipper, new_node), ctx}
    else
      {:cont, zipper, ctx}
    end
  end

  # Credo.Check.Refactor.CondStatements
  def run({{:cond, _, [[{_, [{:->, _, [[head], a]}, {:->, _, [[{:__block__, _, [truthy]}], b]}]}]]}, _} = zipper, ctx)
      when is_atom(truthy) and truthy not in [nil, false] do
    if Config.cond_statements?() do
      if_ast(zipper, head, a, b, ctx)
    else
      {:cont, zipper, ctx}
    end
  end

  # Credo.Check.Readability.WithSingleClause
  # rewrite `with success <- single_statement do body else ...elses end`
  # to `case single_statement do success -> body; ...elses end`
  def run({{:with, m, [{:<-, am, [success, single_statement]}, [body, elses]]}, zm}, ctx) do
    {{:__block__, do_meta, [:do]}, body} = body
    {{:__block__, _, [:else]}, elses} = elses

    elses =
      case elses do
        # unwrap a stab ala `, else: (_ -> :ok)`. these became literals in 1.17
        {:__block__, _, [[{:->, _, _}] = stab]} -> stab
        elses -> elses
      end

    # drops keyword formatting etc
    do_meta = [line: do_meta[:line]]
    clauses = [{{:__block__, am, [:do]}, [{:->, do_meta, [[success], body]} | elses]}]
    end_line = Style.max_line(elses) + 1

    # fun fact: i added the detailed meta just because i noticed it was missing while debugging something ...
    # ... and it fixed the bug 🤷
    case_meta = [
      end_of_expression: [newlines: 1, line: end_line],
      do: do_meta,
      end: [line: end_line],
      line: m[:line]
    ]

    # recurse in case this new case should be rewritten further
    run({{:case, case_meta, [single_statement, clauses]}, zm}, ctx)
  end

  # Credo.Check.Refactor.WithClauses
  def run({{:with, _, children}, _} = zipper, ctx) when is_list(children) do
    do_block? = Enum.any?(children, &Style.do_block?/1)
    arrow_or_match? = Enum.any?(children, &(left_arrow?(&1) || match?({:=, _, _}, &1)))

    cond do
      # we can style this!
      do_block? and arrow_or_match? ->
        style_with_statement(zipper, ctx)

      # `with (head_statements) do: x (else ...)`
      do_block? ->
        # head statements can be the empty list, if it matters
        {head_statements, [[{{:__block__, _, [:do]}, body} | _]]} =
          Enum.split_while(children, &(not Style.do_block?(&1)))

        [first | rest] = head_statements ++ [body]
        # replace this `with` statement with its headers + body
        zipper = zipper |> Zipper.replace(first) |> Zipper.insert_siblings(rest)
        {:cont, zipper, ctx}

      # maybe this isn't a with statement - could be a function named `with` or something.
      true ->
        {:cont, zipper, ctx}
    end
  end

  def run({{:unless, m, [head, do_else]}, _} = zipper, ctx) do
    zipper
    |> Zipper.replace({:if, m, [invert(head), do_else]})
    |> run(ctx)
  end

  def run({{:if, m, children}, _} = zipper, ctx) do
    case children do
      # double negator
      # if !!x, do: y[, else: ...] => if x, do: y[, else: ...]
      [{_, _, [nb]} = na, do_else] when is_negator(na) and is_negator(nb) ->
        zipper |> Zipper.replace({:if, m, [invert(nb), do_else]}) |> run(ctx)

      # Credo.Check.Refactor.NegatedConditionsWithElse
      # if !x, do: y, else: z => if x, do: z, else: y
      [negator, [{do_, do_body}, {else_, else_body}]] when is_negator(negator) ->
        if Config.negated_conditions_with_else?() do
          zipper
          |> Zipper.replace({:if, m, [invert(negator), [{do_, else_body}, {else_, do_body}]]})
          |> run(ctx)
        else
          {:cont, zipper, ctx}
        end

      # drop `else end` and `else: nil`
      [head, [do_block, {_, else_body}]] when is_empty_body(else_body) ->
        {:cont, Zipper.replace(zipper, {:if, m, [head, [do_block]]}), ctx}

      # invert and drop `do: nil`
      [head, [{do_, do_body}, {_, else_body}]] when is_empty_body(do_body) ->
        {:cont, Zipper.replace(zipper, {:if, m, [invert(head), [{do_, else_body}]]}), ctx}

      [head, [do_, else_]] ->
        if Style.max_line(do_) > Style.max_line(else_) do
          # we inverted the if/else blocks of this `if` statement in a previous pass (due to negators or unless)
          # shift comments etc to make it happy now
          if_ast(zipper, head, do_, else_, ctx)
        else
          {:cont, zipper, ctx}
        end

      _ ->
        {:cont, zipper, ctx}
    end
  end

  # Reuse matched terms rather than rebuilding them:
  # `{:ok, val} -> {:ok, val}` => `{:ok, _val} = result -> result`
  def run({{:fn, m, clauses}, _} = zipper, ctx) when is_list(clauses) do
    case reuse_matched_terms(clauses, ctx.comments) do
      {:ok, clauses} -> {:cont, Zipper.replace(zipper, {:fn, m, clauses}), ctx}
      :error -> {:cont, zipper, ctx}
    end
  end

  def run({{{:__block__, _, [kw]} = kw_node, [{:->, _, _} | _] = clauses}, _} = zipper, ctx)
      when kw in [:do, :else, :catch] do
    # only rewrite clauses whose heads we know to be patterns (so not `cond`, typespecs, or arbitrary macros)
    with {[_ | _], _} = keyword_list <- Zipper.up(zipper),
         {{form, _, _}, _} when {form, kw} in @pattern_clause_forms <- Zipper.up(keyword_list),
         {:ok, clauses} <- reuse_matched_terms(clauses, ctx.comments) do
      {:cont, Zipper.replace(zipper, {kw_node, clauses}), ctx}
    else
      _ -> {:cont, zipper, ctx}
    end
  end

  def run({{def, dm, [head, [{{:__block__, _, [:do]} = do_kw, body}]]}, _} = zipper, ctx) when def in [:def, :defp] do
    {{name, cm, args}, guards, rewrap} =
      case head do
        {:when, wm, [call | guards]} -> {call, guards, &{:when, wm, [&1 | guards]}}
        call -> {call, [], & &1}
      end

    with true <- is_list(args),
         {:ok, args, body} <- reuse_matched_term(args, guards, body, ctx.comments) do
      head = rewrap.({name, cm, args})
      {:cont, Zipper.replace(zipper, {def, dm, [head, [{do_kw, body}]]}), ctx}
    else
      _ -> {:cont, zipper, ctx}
    end
  end

  def run(zipper, ctx), do: {:cont, zipper, ctx}

  # `{:ok, clauses}` if any clause was rewritten, so untouched nodes needn't be replaced
  defp reuse_matched_terms(clauses, comments) do
    {clauses, changed?} =
      Enum.map_reduce(clauses, false, fn clause, changed? ->
        case reuse_matched_term_in_clause(clause, comments) do
          {:ok, clause} -> {clause, true}
          :error -> {clause, changed?}
        end
      end)

    if changed? do
      {:ok, clauses}
    else
      :error
    end
  end

  defp reuse_matched_term_in_clause({:->, m, [[{:when, wm, args_and_guard}], body]}, comments) do
    {args, guards} = Enum.split(args_and_guard, -1)

    with {:ok, args, body} <- reuse_matched_term(args, guards, body, comments) do
      {:ok, {:->, m, [[{:when, wm, args ++ guards}], body]}}
    end
  end

  defp reuse_matched_term_in_clause({:->, m, [args, body]}, comments) when is_list(args) do
    with {:ok, args, body} <- reuse_matched_term(args, [], body, comments) do
      {:ok, {:->, m, [args, body]}}
    end
  end

  defp reuse_matched_term_in_clause(_clause, _comments), do: :error

  # If the clause's return value rebuilds one of its argument patterns, bind that argument to a variable and return it.
  defp reuse_matched_term(args, guards, body, comments) do
    {preceding, returned} = split_return_value(body)

    with {index, pattern, existing_name, shape} <- find_matching_arg(args, returned),
         [_ | _] = returned_vars <- shape_vars(shape),
         name = existing_name || new_binding_name(shape),
         # the returned variables (and our binding) must still hold what the pattern matched,
         # and we need to know whether the body references the `_val` we'd rename an unused `val` to
         underscored_names = Enum.map(returned_vars, &:"_#{&1}"),
         {referenced, false} <- scope_usage(preceding, [name | returned_vars] ++ underscored_names),
         head_counts = var_counts(args ++ guards),
         taken? = &(Map.has_key?(head_counts, &1) or &1 in referenced),
         # a name we make up mustn't collide with a variable the clause already uses
         true <- existing_name != nil or not taken?.(name),
         # Replacing the returned term would strand any comments *inside* it (like a comment on one component
         # of a tuple, where the tuple is stretched across multiple lines). This should be very rare.
         false <- has_inner_comments?(returned, comments) do
      unused = unused_vars(returned_vars, pattern, head_counts, referenced)
      underscored = underscore_vars(pattern, unused, taken?)

      arg =
        case Enum.at(args, index) do
          {:=, m, [^pattern, other]} -> {:=, m, [underscored, other]}
          {:=, m, [other, ^pattern]} -> {:=, m, [other, underscored]}
          _ -> {:=, [line: Style.meta(pattern)[:line]], [underscored, {name, [line: Style.meta(pattern)[:line]], nil}]}
        end

      var = {name, [line: Style.meta(returned)[:line]], nil}

      body =
        if preceding == [] do
          var
        else
          {:__block__, elem(body, 1), preceding ++ [var]}
        end

      {:ok, List.replace_at(args, index, arg), body}
    else
      _ -> :error
    end
  end

  # `{preceding_expressions, last_expression}`
  defp split_return_value({:__block__, _, [_, _ | _] = expressions}) do
    {preceding, [last]} = Enum.split(expressions, -1)
    {preceding, last}
  end

  defp split_return_value(body), do: {[], body}

  defp new_binding_name({:tuple, [{:lit, :error} | _]}), do: :error
  defp new_binding_name(_shape), do: :result

  # vars the pattern binds that nothing else references once the body returns the bound variable instead
  defp unused_vars(returned_vars, pattern, head_counts, referenced_in_body) do
    pinned = pinned_vars(pattern)
    Enum.filter(returned_vars, &(head_counts[&1] == 1 and &1 not in referenced_in_body and &1 not in pinned))
  end

  # comments are sorted by line, so we only need to check the first one after the node starts
  defp has_inner_comments?(node, comments) do
    first_line = Style.meta(node)[:line]
    last_line = Style.max_line(node)

    with true <- first_line != nil,
         %{line: line} <- Enum.find(comments, &(&1.line > first_line)) do
      line <= last_line
    else
      _ -> false
    end
  end

  # returns `{index, pattern, existing_binding_name | nil, shape}` for the first arg whose pattern `returned` rebuilds
  defp find_matching_arg(args, returned) do
    args
    |> Enum.with_index()
    |> Enum.find_value(fn {arg, index} ->
      {pattern, binding} = split_binding(arg)

      with {:ok, {kind, _} = shape} when kind in [:tuple, :list] <- term_shape(pattern),
           true <- builds_shape?(returned, shape) do
        {index, pattern, binding, shape}
      else
        _ -> nil
      end
    end)
  end

  # A meta-less description of the term a pattern matches, if it's simple enough to compare.
  # A pattern like `{:ok, %User{} = user}` has the same shape as the expression `{:ok, user}`
  defp term_shape({:__block__, _, [literal]}), do: term_shape(literal)
  defp term_shape({:{}, _, elements}), do: shapes(elements, :tuple)
  defp term_shape({left, right}), do: shapes([left, right], :tuple)
  defp term_shape(list) when is_list(list), do: shapes(list, :list)

  defp term_shape({:|, _, [head, tail]}) do
    with {:ok, head} <- term_shape(head),
         {:ok, tail} <- term_shape(tail) do
      {:ok, {:cons, head, tail}}
    end
  end

  defp term_shape({:^, _, [{name, _, ctx}]}) when is_atom(name) and is_atom(ctx), do: {:ok, {:var, name}}

  defp term_shape({:=, _, _} = match) do
    case split_binding(match) do
      {_pattern, nil} -> :error
      {_pattern, name} -> {:ok, {:var, name}}
    end
  end

  defp term_shape({_, _, ctx} = var) when is_atom(ctx) do
    if name = reusable_var(var) do
      {:ok, {:var, name}}
    else
      :error
    end
  end

  defp term_shape(literal) when is_atom(literal) or is_number(literal) or is_binary(literal), do: {:ok, {:lit, literal}}
  defp term_shape(_), do: :error

  defp shapes(asts, kind) do
    asts
    |> Enum.reduce_while([], fn ast, acc ->
      case term_shape(ast) do
        {:ok, shape} -> {:cont, [shape | acc]}
        :error -> {:halt, :error}
      end
    end)
    |> case do
      :error -> :error
      shapes -> {:ok, {kind, Enum.reverse(shapes)}}
    end
  end

  # Whether the expression builds exactly the term `shape` describes.
  # Walks the expression only as far as the (typically tiny) shape goes, so huge returned literals bail out quickly.
  defp builds_shape?({:__block__, _, [literal]}, shape), do: builds_shape?(literal, shape)
  defp builds_shape?({:{}, _, elements}, {:tuple, shapes}), do: all_build_shapes?(elements, shapes)
  defp builds_shape?({left, right}, {:tuple, shapes}), do: all_build_shapes?([left, right], shapes)
  defp builds_shape?(list, {:list, shapes}) when is_list(list), do: all_build_shapes?(list, shapes)
  defp builds_shape?({:|, _, [head, tail]}, {:cons, h, t}), do: builds_shape?(head, h) and builds_shape?(tail, t)
  defp builds_shape?({_, _, ctx} = var, {:var, name}) when is_atom(ctx), do: reusable_var(var) == name
  # strict equality, since `1` and `1.0` are different terms
  defp builds_shape?(literal, {:lit, value}), do: literal === value
  defp builds_shape?(_, _), do: false

  defp all_build_shapes?([ast | asts], [shape | shapes]),
    do: builds_shape?(ast, shape) and all_build_shapes?(asts, shapes)

  defp all_build_shapes?([], []), do: true
  defp all_build_shapes?(_, _), do: false

  defp shape_vars({:var, name}), do: [name]
  defp shape_vars({:lit, _}), do: []
  defp shape_vars({:cons, head, tail}), do: Enum.uniq(shape_vars(head) ++ shape_vars(tail))
  defp shape_vars({_kind, shapes}), do: shapes |> Enum.flat_map(&shape_vars/1) |> Enum.uniq()

  # the name of a variable we can reference (not `_` or `_foo`)
  defp reusable_var({name, _, ctx}) when is_atom(name) and is_atom(ctx) do
    if not String.starts_with?(Atom.to_string(name), "_") do
      name
    end
  end

  defp reusable_var(_), do: nil

  # `pattern = var` or `var = pattern` => `{pattern, var_name}`; anything else => `{ast, nil}`
  defp split_binding({:=, _, [left, right]} = ast) do
    cond do
      name = reusable_var(right) -> {left, name}
      name = reusable_var(left) -> {right, name}
      true -> {ast, nil}
    end
  end

  defp split_binding(ast), do: {ast, nil}

  defp var_counts(asts) do
    asts
    |> Macro.prewalk(%{}, fn
      {name, _, ctx} = node, acc when is_atom(name) and is_atom(ctx) -> {node, Map.update(acc, name, 1, &(&1 + 1))}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end

  defp pinned_vars(pattern) do
    pattern
    |> Macro.prewalk([], fn
      {:^, _, [{name, _, _}]} = node, acc -> {node, [name | acc]}
      node, acc -> {node, acc}
    end)
    |> elem(1)
  end

  # Walks expressions evaluated in a clause's own scope, returning `{referenced, rebound?}`:
  # which of `names` they reference (ignoring inner scopes where a new binding shadows the name),
  # and whether they rebind any of `names` in the clause's scope.
  #
  # Errs toward over-reporting both: missing a reference would underscore a variable that's still used.
  # So, only constructs whose scoping we know (`fn`, `case`, `receive`, `try`, `for`, `with`) can shadow a name,
  # and any other match (say, in an `if` body or a macro's arguments) counts as rebinding it.
  defp scope_usage(asts, names), do: usage(asts, MapSet.new(names), true, {MapSet.new(), false})

  defp usage(asts, visible, top?, acc) when is_list(asts), do: Enum.reduce(asts, acc, &usage(&1, visible, top?, &2))

  defp usage({name, _, ctx}, visible, _top?, {refs, rebound?}) when is_atom(name) and is_atom(ctx) do
    if name in visible, do: {MapSet.put(refs, name), rebound?}, else: {refs, rebound?}
  end

  defp usage({:fn, _, clauses}, visible, _top?, acc) when is_list(clauses), do: clauses_usage(clauses, visible, acc)

  defp usage({:=, _, [pattern, expr]}, visible, top?, acc) do
    {bound, {refs, rebound?}} = pattern_usage(pattern, visible, acc)
    usage(expr, visible, top?, {refs, rebound? or (top? and not MapSet.disjoint?(bound, visible))})
  end

  defp usage({form, _, [_ | _] = args}, visible, top?, acc) when form in [:case, :receive, :try] do
    Enum.reduce(args, acc, &blocks_usage(form, &1, visible, visible, top?, &2))
  end

  # each generator or match narrows what later clauses and the `do` body can see of the outer scope
  defp usage({form, _, [_ | _] = args}, visible, top?, acc) when form in [:for, :with] do
    {_inner, acc} =
      Enum.reduce(args, {visible, acc}, fn
        {op, _, [pattern, expr]}, {inner, acc} when op in [:<-, :=] ->
          acc = usage(expr, inner, false, acc)
          {bound, acc} = pattern_usage(pattern, inner, acc)
          {MapSet.difference(inner, bound), acc}

        [{{:__block__, _, [_]}, _} | _] = blocks, {inner, acc} ->
          {inner, blocks_usage(form, blocks, visible, inner, top?, acc)}

        filter, {inner, acc} ->
          {inner, usage(filter, inner, false, acc)}
      end)

    acc
  end

  defp usage({head, _, args}, visible, top?, acc) when is_list(args), do: usage([head | args], visible, top?, acc)
  defp usage({left, right}, visible, top?, acc), do: usage([left, right], visible, top?, acc)
  defp usage(_literal, _visible, _top?, acc), do: acc

  # `do` sees the bindings of a `for`/`with`'s generators; `else` and options like `reduce:` see only the outer scope
  defp blocks_usage(form, [{{:__block__, _, [_]}, _} | _] = blocks, outer, inner, top?, acc) do
    Enum.reduce(blocks, acc, fn
      {{:__block__, _, [kw]}, value}, acc when {form, kw} in @pattern_clause_forms ->
        clauses_usage(value, if(kw == :do, do: inner, else: outer), acc)

      {{:__block__, _, [kw]}, value}, acc when kw in [:do, :else, :after, :rescue, :catch] ->
        usage(value, if(kw == :do, do: inner, else: outer), false, acc)

      {_option, value}, acc ->
        usage(value, outer, top?, acc)
    end)
  end

  defp blocks_usage(_form, ast, outer, _inner, top?, acc), do: usage(ast, outer, top?, acc)

  # each clause's head shadows the names it binds for the rest of the clause
  defp clauses_usage([{:->, _, _} | _] = clauses, visible, acc) do
    Enum.reduce(clauses, acc, fn
      {:->, _, [heads, body]}, acc ->
        {bound, acc} = pattern_usage(heads, visible, acc)
        usage(body, MapSet.difference(visible, bound), false, acc)

      other, acc ->
        usage(other, visible, false, acc)
    end)
  end

  defp clauses_usage(body, visible, acc), do: usage(body, visible, false, acc)

  # returns `{names_bound, acc}`, where `acc` includes what the pattern's pins, guards, and bitstring sizes reference
  defp pattern_usage(pattern, visible, acc) do
    {_, {bound, refs, guards}} =
      Macro.prewalk(pattern, {MapSet.new(), [], []}, fn
        {:when, _, [_ | _] = args}, {bound, refs, guards} ->
          {patterns, [guard]} = Enum.split(args, -1)
          {{:__block__, [], patterns}, {bound, refs, [guard | guards]}}

        {op, _, _} = ref, {bound, refs, guards} when op in [:^, :@, :unquote, :unquote_splicing] ->
          {nil, {bound, [ref | refs], guards}}

        {:"::", _, [left, right]}, {bound, refs, guards} ->
          {{:__block__, [], [left]}, {bound, [right | refs], guards}}

        {name, _, ctx} = var, {bound, refs, guards} when is_atom(name) and is_atom(ctx) ->
          {var, {MapSet.put(bound, name), refs, guards}}

        node, state ->
          {node, state}
      end)

    acc = usage(refs, visible, false, acc)
    {bound, usage(guards, MapSet.difference(visible, bound), false, acc)}
  end

  # `{:ok, %User{} = user}` => `{:ok, %User{}}`; `{:ok, val}` => `{:ok, _val}` (or `{:ok, _}` if `_val` is taken)
  defp underscore_vars(pattern, [], _taken?), do: pattern

  defp underscore_vars(pattern, unused, taken?) do
    unused? = &(reusable_var(&1) in unused)

    Macro.prewalk(pattern, fn
      {:=, _, [left, right]} = node ->
        cond do
          unused?.(right) -> left
          unused?.(left) -> right
          true -> node
        end

      {name, m, ctx} = var when is_atom(ctx) ->
        cond do
          not unused?.(var) -> var
          # underscored variables still bind, so a second `_val` would require both values to match
          taken?.(:"_#{name}") -> {:_, m, ctx}
          true -> {:"_#{name}", m, ctx}
        end

      node ->
        node
    end)
  end

  # with statements can do _a lot_, so this beast of a function likewise does a lot.
  defp style_with_statement({{:with, with_meta, children}, _} = zipper, ctx) do
    {preroll, children} =
      children
      |> Enum.map(fn
        # `_ <- rhs` => `rhs`
        {:<-, _, [{:_, _, _}, rhs]} -> rhs
        # `lhs <- rhs` => `lhs = rhs`
        {:<-, m, [{atom, _, nil} = lhs, rhs]} when is_atom(atom) -> {:=, m, [lhs, rhs]}
        child -> child
      end)
      |> Enum.split_while(&(not left_arrow?(&1)))

    # after rewriting `x <- y()` to `x = y()` there are no more arrows.
    # this never should've been a with statement at all! we can just replace it with assignments
    if Enum.empty?(children) do
      {:cont, replace_with_statement(zipper, preroll), ctx}
    else
      [[{{_, do_meta, _} = do_block, do_body} | elses] | reversed_clauses] = Enum.reverse(children)
      {postroll, reversed_clauses} = Enum.split_while(reversed_clauses, &(not left_arrow?(&1)))
      [{:<-, final_clause_meta, [lhs, rhs]} = _final_clause | rest] = reversed_clauses

      # drop singleton identity else clauses like `else foo -> foo end`
      elses =
        with [{{_, _, [:else]}, [{:->, _, [[left], right]}]}] <- elses,
             true <- nodes_equivalent?(left, right),
             do: [],
             else: (_ -> elses)

      # Remove Redundant body
      {postroll, reversed_clauses, do_body} =
        if Enum.empty?(postroll) and Enum.empty?(elses) and nodes_equivalent?(lhs, do_body) do
          # removing redundant RHS can expose more non-arrows behind it, so repeat our postroll process
          {postroll, reversed_clauses} = Enum.split_while(rest, &(not left_arrow?(&1)))
          {postroll, reversed_clauses, rhs}
        else
          {postroll, reversed_clauses, do_body}
        end

      # Put the postroll into the body
      {reversed_clauses, do_body} =
        if Enum.any?(postroll) do
          {node, do_body_meta, do_children} = do_body
          do_children = if node == :__block__, do: do_children, else: [do_body]
          do_body = {:__block__, Keyword.take(do_body_meta, [:line]), Enum.reverse(postroll, do_children)}
          {reversed_clauses, do_body}
        else
          {reversed_clauses, do_body}
        end

      final_clause_line = final_clause_meta[:line]

      do_line =
        cond do
          do_meta[:format] == :keyword && final_clause_line + 1 >= do_meta[:line] -> do_meta[:line]
          do_meta[:format] == :keyword -> final_clause_line + 1
          true -> final_clause_line
        end

      do_block = Macro.update_meta(do_block, &Keyword.put(&1, :line, do_line))
      # disable keyword `, do:` since there will be multiple statements in the body
      with_meta =
        if Enum.any?(postroll),
          do: Keyword.merge(with_meta, do: [line: with_meta[:line]], end: [line: Style.max_line(children) + 1]),
          else: with_meta

      with_children = Enum.reverse(reversed_clauses, [[{do_block, do_body} | elses]])
      zipper = Zipper.replace(zipper, {:with, with_meta, with_children})

      cond do
        # oops! RedundantWithClauseResult removed the final arrow in this. no more need for a with statement!
        Enum.empty?(reversed_clauses) ->
          {:cont, replace_with_statement(zipper, preroll ++ with_children), ctx}

        # recurse if the # of `<-` have changed (this `with` could now be eligible for a `case` rewrite)
        Enum.any?(preroll) ->
          # put the preroll before the with statement in either a block we create or the existing parent block
          zipper
          |> Style.find_nearest_block()
          |> Zipper.prepend_siblings(preroll)
          |> run(ctx)

        # the # of `<-` changed, so we should have another look at this with statement
        Enum.any?(postroll) ->
          run(zipper, ctx)

        true ->
          # of clauses didn't change, so don't reecurse or we'll loop FOREEEVEERR
          {:cont, zipper, ctx}
      end
    end
  end

  # `with a <- b(), c <- d(), do: :ok, else: (_ -> :error)`
  # =>
  # `a = b(); c = d(); :ok`
  defp replace_with_statement(zipper, preroll) do
    [[{_do, do_body} | _elses] | preroll] = Enum.reverse(preroll)

    block =
      case do_body do
        {:__block__, _, [{_, _, _} | _] = children} ->
          Enum.reverse(preroll, children)

        _ ->
          # RedundantWithClauseResult except we rewrote the `<-` to an `=`
          # `with a, b, x <- y(), do: x` => `a; b; y`
          case preroll do
            [{:=, _, [lhs, rhs]} | rest] ->
              if nodes_equivalent?(lhs, do_body),
                do: Enum.reverse(rest, [rhs]),
                else: Enum.reverse(preroll, [do_body])

            _ ->
              Enum.reverse(preroll, [do_body])
          end
      end

    case Style.ensure_block_parent(zipper) do
      {:ok, zipper} ->
        zipper
        |> Zipper.prepend_siblings(block)
        |> Zipper.remove()

      :error ->
        # this is a very sad case, where the `with` is an arg to a function or the rhs of an assignment.
        # for now, just hacking a block with parens where the with use to be
        # x = with a, b, c, do: d
        # =>
        # x =
        #   (
        #     a
        #     b
        #     c
        #     d
        #   )
        # @TODO would be nice to change to
        # a
        # b
        # c
        # x = d
        Zipper.update(zipper, fn {:with, meta, _} ->
          {:__block__, Keyword.take(meta, [:line]), block}
        end)
    end
  end

  defp left_arrow?({:<-, _, _}), do: true
  defp left_arrow?(_), do: false

  defp nodes_equivalent?(a, b), do: Style.without_meta(a) == Style.without_meta(b)

  defp if_ast(zipper, head, {_, _, _} = do_body, {_, _, _} = else_body, ctx) do
    do_ = {{:__block__, [line: nil], [:do]}, do_body}
    else_ = {{:__block__, [line: nil], [:else]}, else_body}
    if_ast(zipper, head, do_, else_, ctx)
  end

  defp if_ast(zipper, {_, meta, _} = head, {do_kw, do_body}, {else_kw, else_body}, ctx) do
    line = meta[:line]
    # ... why am i doing this again? hmm.
    do_body = Macro.update_meta(do_body, &Keyword.delete(&1, :end_of_expression))
    else_body = Macro.update_meta(else_body, &Keyword.delete(&1, :end_of_expression))

    max_do_line = Style.max_line(do_body)
    max_else_line = Style.max_line(else_body)
    end_line = max(max_do_line, max_else_line)

    # Change ast meta and comment lines to fit the `if` ast
    {do_, else_, comments} =
      if max_do_line >= max_else_line do
        # we're swapping the ordering of two blocks of code
        # and so must swap the lines of the ast & comments to keep comments where they belong!
        # the math is: move B up by the length of A, and move A down by the length of B plus one (for the else keyword)
        else_size = max_else_line - line
        do_size = max_do_line - max_else_line

        shifts = [
          # move comments in the `else_body` down by the size of the `do_body`
          {line..max_else_line, do_size},
          # move comments in `do_body` up by the size of the `else_body`
          {(max_else_line + 1)..max_do_line, -else_size}
        ]

        do_ = {Style.set_line(do_kw, line), Style.shift_line(do_body, -else_size)}
        else_ = {Style.set_line(else_kw, max_else_line), Style.shift_line(else_body, do_size)}
        {do_, else_, Style.shift_comments(ctx.comments, shifts)}
      else
        # much simpler case -- just scootch things in the else down by 1 for the `else` keyword.
        do_ = {{:__block__, [line: line], [:do]}, do_body}
        else_ = Style.shift_line({{:__block__, [line: max_do_line], [:else]}, else_body}, 1)
        {do_, else_, Style.shift_comments(ctx.comments, max_do_line..max_else_line, 1)}
      end

    zipper
    |> Zipper.replace({:if, [do: [line: line], end: [line: end_line], line: line], [head, [do_, else_]]})
    |> run(%{ctx | comments: comments})
  end

  defp invert({:!=, m, [a, b]}), do: {:==, m, [a, b]}
  defp invert({:!==, m, [a, b]}), do: {:===, m, [a, b]}
  defp invert({:==, m, [a, b]}), do: {:!=, m, [a, b]}
  defp invert({:===, m, [a, b]}), do: {:!==, m, [a, b]}
  defp invert({:!, _, [condition]}), do: condition
  defp invert({:not, _, [condition]}), do: condition
  defp invert({:in, m, [_, _]} = ast), do: {:not, m, [ast]}
  defp invert({_, m, _} = ast), do: {:!, [line: m[:line]], [ast]}
end
