# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.SingleNode do
  @moduledoc """
  Simple 1-1 rewrites all crammed into one module to make for more efficient traversals

  Credo Rules addressed:

  * Credo.Check.Consistency.ParameterPatternMatching
  * Credo.Check.Readability.LargeNumbers
  * Credo.Check.Readability.ParenthesesOnZeroArityDefs
  * Credo.Check.Readability.PreferImplicitTry
  * Credo.Check.Readability.StringSigils
  * Credo.Check.Readability.WithSingleClause
  * Credo.Check.Refactor.CondStatements
  * Credo.Check.Refactor.RedundantWithClauseResult
  * Credo.Check.Refactor.WithClauses
  * Credo.Check.Warning.ExpensiveEmptyEnumCheck
  """

  @behaviour Quokka.Style

  alias Quokka.Zipper

  @closing_delimiters [~s|"|, ")", "}", "|", "]", "'", ">", "/"]

  # `|> Timex.now()` => `|> Timex.now()`
  # skip over pipes into `Timex.now/1` so that we don't accidentally rewrite it as DateTime.utc_now/1
  def run({{:|>, _, [_, {{:., _, [{:__aliases__, _, [:Timex]}, :now]}, _, []}]}, _} = zipper, ctx),
    do: {:skip, zipper, ctx}

  # Skip expensive empty enum check rewrites when inside guard clauses
  def run({node, meta} = zipper, ctx) when elem(node, 0) in [:>, :<, :==, :===] do
    if in_guard?(zipper) do
      {:cont, zipper, ctx}
    else
      {:cont, {style(node), meta}, ctx}
    end
  end

  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

  # rewrite double-quote strings with >= 4 escaped double-quotes as sigils
  defp style({:__block__, [{:delimiter, ~s|"|} | meta], [string]} = node) when is_binary(string) do
    # running a regex against every double-quote delimited string literal in a codebase doesn't have too much impact
    # on adobe's internal codebase, but perhaps other codebases have way more literals where this'd have an impact?
    if string =~ ~r/".*".*".*"/ do
      # choose whichever delimiter would require the least # of escapes,
      # ties being broken by our stylish ordering of delimiters (reflected in the 1-8 values)
      {closer, _} =
        string
        |> String.codepoints()
        |> Stream.filter(&(&1 in @closing_delimiters))
        |> Stream.concat(@closing_delimiters)
        |> Enum.frequencies()
        |> Enum.min_by(fn
          {~s|"|, count} -> {count, 1}
          {")", count} -> {count, 2}
          {"}", count} -> {count, 3}
          {"|", count} -> {count, 4}
          {"]", count} -> {count, 5}
          {"'", count} -> {count, 6}
          {">", count} -> {count, 7}
          {"/", count} -> {count, 8}
        end)

      delimiter =
        case closer do
          ")" -> "("
          "}" -> "{"
          "]" -> "["
          ">" -> "<"
          closer -> closer
        end

      {:sigil_s, [{:delimiter, delimiter} | meta], [{:<<>>, [line: meta[:line]], [string]}, []]}
    else
      node
    end
  end

  # Add / Correct `_` location in large numbers. Formatter handles large number (>5 digits) rewrites,
  # but doesn't rewrite typos like `100_000_0`, so it's worthwhile to have Quokka do this
  #
  # `?-` isn't part of the number node - it's its parent - so all numbers are positive at this point
  defp style({:__block__, meta, [number]}) when is_number(number) do
    if number > Quokka.Config.large_numbers_gt() do
      # Checking here rather than in the anonymous function due to compiler bug https://github.com/elixir-lang/elixir/issues/10485
      integer? = is_integer(number)

      meta =
        Keyword.update!(meta, :token, fn
          "0x" <> _ = token ->
            token

          "0b" <> _ = token ->
            token

          "0o" <> _ = token ->
            token

          token when integer? ->
            delimit(token)

          # is float
          token ->
            [int_token, decimals] = String.split(token, ".")
            "#{delimit(int_token)}.#{decimals}"
        end)

      {:__block__, meta, [number]}
    else
      {:__block__, meta, [number]}
    end
  end

  ## INEFFICIENT FUNCTION REWRITES
  # Keep in mind when rewriting a `/n::pos_integer` arity function here that it should also be added
  # to the pipes rewriting rules, where it will appear as `/n-1`

  # Enum.into(enum, empty_map[, ...]) => Map.new(enum[, ...])
  defp style({{:., _, [{:__aliases__, _, [:Enum]}, :into]} = into, m, [enum, collectable | rest]} = node) do
    if replacement = replace_into(into, collectable, rest),
      do: {replacement, m, [enum | rest]},
      else: node
  end

  # lhs |> Enum.into(%{}, ...) => lhs |> Map.new(...)
  defp style({:|>, meta, [lhs, {{:., _, [{_, _, [:Enum]}, :into]} = into, m, [collectable | rest]}]} = node) do
    if replacement = replace_into(into, collectable, rest),
      do: {:|>, meta, [lhs, {replacement, m, rest}]},
      else: node
  end

  for m <- [:Map, :Keyword] do
    # lhs |> Map.merge(%{key: value}) => lhs |> Map.put(:key, value)
    defp style(
           {:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [{:%{}, _, [{key, value}]}]}]} = node
         ) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {:|>, pm, [lhs, {{:., dm, [module, :put]}, m, [key, value]}]},
        else: node
    end

    # lhs |> Map.merge(key: value) => lhs |> Map.put(:key, value)
    defp style({:|>, pm, [lhs, {{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [[{key, value}]]}]} = node) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {:|>, pm, [lhs, {{:., dm, [module, :put]}, m, [key, value]}]},
        else: node
    end

    # Map.merge(foo, %{one_key: :bar}) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, {:%{}, _, [{key, value}]}]} = node) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {{:., dm, [module, :put]}, m, [lhs, key, value]},
        else: node
    end

    # Map.merge(foo, one_key: :bar) => Map.put(foo, :one_key, :bar)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :merge]}, m, [lhs, [{key, value}]]} = node) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {{:., dm, [module, :put]}, m, [lhs, key, value]},
        else: node
    end

    # lhs |> Map.drop([key]) => lhs |> Map.delete(key)
    defp style({{:., dm, [{_, _, [unquote(m)]} = module, :drop]}, m, [{:__block__, _, [[{op, _, _} = key]]}]} = node)
         when op != :| do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {{:., dm, [module, :delete]}, m, [key]},
        else: node
    end

    # Map.drop(foo, [one_key]) => Map.delete(foo, one_key)
    defp style(
           {{:., dm, [{_, _, [unquote(m)]} = module, :drop]}, m, [lhs, {:__block__, _, [[{op, _, _} = key]]}]} = node
         )
         when op != :| do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {{:., dm, [module, :delete]}, m, [lhs, key]},
        else: node
    end
  end

  # Timex.now() => DateTime.utc_now()
  defp style({{:., dm, [{:__aliases__, am, [:Timex]}, :now]}, funm, []} = node) do
    if Quokka.Config.inefficient_function_rewrites?(),
      do: {{:., dm, [{:__aliases__, am, [:DateTime]}, :utc_now]}, funm, []},
      else: node
  end

  # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :lt => {DateTime,NaiveDateTime,Time,Date}.before?(a, b)
  # {DateTime,NaiveDateTime,Time,Date}.compare(a, b) == :gt => {DateTime,NaiveDateTime,Time,Date}.after?(a, b)
  defp style(
         {:==, _, [{{:., dm, [{:__aliases__, am, [mod]}, :compare]}, funm, args}, {:__block__, _, [result]}]} = node
       )
       when mod in ~w[DateTime NaiveDateTime Time Date]a and result in [:lt, :gt] do
    if Quokka.Config.inefficient_function_rewrites?() do
      fun = if result == :lt, do: :before?, else: :after?
      {{:., dm, [{:__aliases__, am, [mod]}, fun]}, funm, args}
    else
      node
    end
  end

  # `Credo.Check.Readability.PreferImplicitTry`
  defp style({def, dm, [head, [{_, {:try, _, [try_children]}}]]}) when def in ~w(def defp)a,
    do: style({def, dm, [head, try_children]})

  # Remove parens from 0 arity funs (Credo.Check.Readability.ParenthesesOnZeroArityDefs)
  defp style({def, dm, [{fun, funm, []} | rest]} = node) when def in ~w(def defp)a and is_atom(fun) do
    if Quokka.Config.zero_arity_parens?() == false,
      do: style({def, dm, [{fun, Keyword.delete(funm, :closing), nil} | rest]}),
      else: node
  end

  # Add parens to 0 arity funs (Credo.Check.Readability.ParenthesesOnZeroArityDefs)
  defp style({def, dm, [{fun, funm, nil} | rest]} = node) when def in ~w(def defp)a and is_atom(fun) do
    if Quokka.Config.zero_arity_parens?() == true,
      do: {def, dm, [{fun, Keyword.put(funm, :closing, line: funm[:line]), []} | rest]},
      else: node
  end

  defp style({def, dm, [{fun, funm, params} | rest]}) when def in ~w(def defp)a,
    do: {def, dm, [{fun, funm, put_matches_on_right(params)} | rest]}

  # `Enum.reverse(foo) ++ bar` => `Enum.reverse(foo, bar)`
  defp style({:++, _, [{{:., _, [{_, _, [:Enum]}, :reverse]} = reverse, r_meta, [lhs]}, rhs]}),
    do: {reverse, r_meta, [lhs, rhs]}

  @literal_zero_pattern quote do: {:__block__, _, [0]}
  @enum_count_pattern quote do: {{:., var!(m), [{_, _, [:Enum]}, :count]}, _, [var!(enum)]}
  @enum_count_with_fn_pattern quote do: {{:., var!(m), [{_, _, [:Enum]}, :count]}, _, [var!(enum), var!(func)]}
  @length_pattern quote do: {:length, var!(m), [var!(enum)]}

  for {lhs, rhs} <- [
        # Enum.count(enum) == 0 => Enum.empty?(enum)
        {@enum_count_pattern, @literal_zero_pattern},
        # 0 == Enum.count(enum) => Enum.empty?(enum)
        {@literal_zero_pattern, @enum_count_pattern},
        # length(enum) == 0 => Enum.empty?(enum)
        {@length_pattern, @literal_zero_pattern},
        # 0 == length(enum) => Enum.empty?(enum)
        {@literal_zero_pattern, @length_pattern}
      ] do
    defp style({op, _, [unquote(lhs), unquote(rhs)]} = node) when op in [:==, :===] do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {{:., m, [{:__aliases__, m, [:Enum]}, :empty?]}, m, [enum]},
        else: node
    end
  end

  for {lhs, rhs} <- [
        # Enum.count(enum, fn) == 0 => not Enum.any?(enum, fn)
        {@enum_count_with_fn_pattern, @literal_zero_pattern},
        # 0 == Enum.count(enum, fn) => not Enum.any?(enum, fn)
        {@literal_zero_pattern, @enum_count_with_fn_pattern}
      ] do
    defp style({op, _, [unquote(lhs), unquote(rhs)]} = node) when op in [:==, :===] do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {:not, m, [{{:., m, [{:__aliases__, m, [:Enum]}, :any?]}, m, [enum, func]}]},
        else: node
    end
  end

  @pipe_to_length_pattern quote do: {:|>, var!(pm), [var!(lhs), {:length, var!(m), []}]}
  @pipe_to_count_pattern quote do: {:|>, var!(pm), [var!(lhs), {{:., var!(m), [{_, _, [:Enum]}, :count]}, _, []}]}
  @pipe_to_count_with_fn_pattern quote do:
                                         {:|>, var!(pm),
                                          [var!(lhs), {{:., var!(m), [{_, _, [:Enum]}, :count]}, _, [var!(func)]}]}

  for {lhs, rhs} <- [
        # foo |> bar() |> length() == 0 => foo |> bar() |> Enum.empty?()
        {@pipe_to_length_pattern, @literal_zero_pattern},
        # 0 == foo |> bar() |> length() => foo |> bar() |> Enum.empty?()
        {@literal_zero_pattern, @pipe_to_length_pattern},
        # foo |> bar() |> Enum.count() == 0 => foo |> bar() |> Enum.empty?()
        {@pipe_to_count_pattern, @literal_zero_pattern},
        # 0 == foo |> bar() |> Enum.count() => foo |> bar() |> Enum.empty?()
        {@literal_zero_pattern, @pipe_to_count_pattern}
      ] do
    defp style({op, _, [unquote(lhs), unquote(rhs)]} = node) when op in [:==, :===] do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {:|>, pm, [lhs, {{:., m, [{:__aliases__, m, [:Enum]}, :empty?]}, m, []}]},
        else: node
    end
  end

  for {lhs, rhs, op} <- [
        # foo |> bar() |> Enum.count(&my_fn/1) > 0 => foo |> bar() |> Enum.any?(&my_fn/1)
        {@pipe_to_count_with_fn_pattern, @literal_zero_pattern, :>},
        # 0 < foo |> bar() |> Enum.count(&my_fn/1) => foo |> bar() |> Enum.any?(&my_fn/1)
        {@literal_zero_pattern, @pipe_to_count_with_fn_pattern, :<},
        # foo |> bar() |> Enum.count(fn v -> length(v) end) != 0 => foo |> bar() |> Enum.any?(fn v -> length(v) end)
        {@pipe_to_count_with_fn_pattern, @literal_zero_pattern, :!=},
        # 0 != foo |> bar() |> Enum.count(fn v -> length(v) end) => foo |> bar() |> Enum.any?(fn v -> length(v) end)
        {@literal_zero_pattern, @pipe_to_count_with_fn_pattern, :!=}
      ] do
    defp style({unquote(op), _, [unquote(lhs), unquote(rhs)]} = node) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {:|>, pm, [lhs, {{:., m, [{:__aliases__, m, [:Enum]}, :any?]}, m, [func]}]},
        else: node
    end
  end

  for {lhs, rhs, op} <- [
        # Enum.count(enum) > 0 => not Enum.empty?(enum)
        {@enum_count_pattern, @literal_zero_pattern, :>},
        # Enum.count(enum) != 0 => not Enum.empty?(enum)
        {@enum_count_pattern, @literal_zero_pattern, :!=},
        # 0 < Enum.count(enum) => not Enum.empty?(enum)
        {@literal_zero_pattern, @enum_count_pattern, :<},
        # 0 != Enum.count(enum) => not Enum.empty?(enum)
        {@literal_zero_pattern, @enum_count_pattern, :!=},
        # length(enum) > 0 => not Enum.empty?(enum)
        {@length_pattern, @literal_zero_pattern, :>},
        # length(enum) != 0 => not Enum.empty?(enum)
        {@length_pattern, @literal_zero_pattern, :!=},
        # 0 < length(enum) => not Enum.empty?(enum)
        {@literal_zero_pattern, @length_pattern, :<},
        # 0 != length(enum) => not Enum.empty?(enum)
        {@literal_zero_pattern, @length_pattern, :!=}
      ] do
    defp style({unquote(op), _, [unquote(lhs), unquote(rhs)]} = node) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {:not, m, [{{:., m, [{:__aliases__, m, [:Enum]}, :empty?]}, m, [enum]}]},
        else: node
    end
  end

  for {lhs, rhs, op} <- [
        # Enum.count(enum, fn) > 0 => Enum.any?(enum, fn)
        {@enum_count_with_fn_pattern, @literal_zero_pattern, :>},
        # Enum.count(enum, fn) != 0 => Enum.any?(enum, fn)
        {@enum_count_with_fn_pattern, @literal_zero_pattern, :!=},
        # 0 < Enum.count(enum, fn) => Enum.any?(enum, fn)
        {@literal_zero_pattern, @enum_count_with_fn_pattern, :<},
        # 0 != Enum.count(enum, fn) => Enum.any?(enum, fn)
        {@literal_zero_pattern, @enum_count_with_fn_pattern, :!=}
      ] do
    defp style({unquote(op), _, [unquote(lhs), unquote(rhs)]} = node) do
      if Quokka.Config.inefficient_function_rewrites?(),
        do: {{:., m, [{:__aliases__, m, [:Enum]}, :any?]}, m, [enum, func]},
        else: node
    end
  end

  # ARROW REWRITES
  # `with`, `for` left arrow - if only we could write something this trivial for `->`!
  defp style({:<-, cm, [lhs, rhs]}), do: {:<-, cm, [put_matches_on_right(lhs), rhs]}

  # there's complexity to `:->` due to `cond` also utilizing the symbol but with different semantics.
  # thus, we have to have a clause for each place that `:->` can show up
  # `with` elses
  defp style({{:__block__, _, [:else]} = else_, arrows}), do: {else_, rewrite_arrows(arrows)}

  defp style({:case, cm, [head, [{do_, arrows}]]}), do: {:case, cm, [head, [{do_, rewrite_arrows(arrows)}]]}

  defp style({:fn, m, arrows}), do: {:fn, m, rewrite_arrows(arrows)}

  defp style({:to_timeout, meta, [[{{:__block__, um, [unit]}, {:*, _, [left, right]}}]]} = node)
       when unit in ~w(day hour minute second millisecond)a do
    [l, r] =
      Enum.map([left, right], fn
        {_, _, [x]} -> x
        _ -> nil
      end)

    {step, next_unit} =
      case unit do
        :day -> {7, :week}
        :hour -> {24, :day}
        :minute -> {60, :hour}
        :second -> {60, :minute}
        :millisecond -> {1000, :second}
      end

    if step in [l, r] do
      n = if l == step, do: right, else: left
      style({:to_timeout, meta, [[{{:__block__, um, [next_unit]}, n}]]})
    else
      node
    end
  end

  defp style({:to_timeout, meta, [[{{:__block__, um, [unit]}, {:__block__, tm, [n]}}]]} = node) do
    step_up =
      case {unit, n} do
        {:day, 7} -> :week
        {:hour, 24} -> :day
        {:minute, 60} -> :hour
        {:second, 60} -> :minute
        {:millisecond, 1000} -> :second
        _ -> nil
      end

    if step_up do
      {:to_timeout, meta, [[{{:__block__, um, [step_up]}, {:__block__, [token: "1", line: tm[:line]], [1]}}]]}
    else
      node
    end
  end

  defp style(node), do: node

  defp replace_into({:., dm, [{_, am, _} = enum, _]}, collectable, rest) do
    case Quokka.Config.inefficient_function_rewrites?() and collectable do
      {{:., _, [{_, _, [mod]}, :new]}, _, []} when mod in ~w(Map Keyword MapSet)a ->
        {:., dm, [{:__aliases__, am, [mod]}, :new]}

      {:%{}, _, []} ->
        {:., dm, [{:__aliases__, am, [:Map]}, :new]}

      {:__block__, _, [[]]} ->
        if Enum.empty?(rest), do: {:., dm, [enum, :to_list]}, else: {:., dm, [enum, :map]}

      _ ->
        nil
    end
  end

  defp rewrite_arrows(arrows) when is_list(arrows),
    do: Enum.map(arrows, fn {:->, m, [lhs, rhs]} -> {:->, m, [put_matches_on_right(lhs), rhs]} end)

  defp rewrite_arrows(macros_or_something_crazy_oh_no_abooort), do: macros_or_something_crazy_oh_no_abooort

  defp put_matches_on_right(ast) do
    Macro.prewalk(ast, fn
      # `_ = var ->` => `var ->`
      {:=, _, [{:_, _, nil}, var]} -> var
      # `var = _ ->` => `var ->`
      {:=, _, [var, {:_, _, nil}]} -> var
      # `var = *match*`  -> `*match -> var`
      {:=, m, [{_, _, nil} = var, match]} -> {:=, m, [match, var]}
      node -> node
    end)
  end

  defp delimit(token), do: token |> String.to_charlist() |> remove_underscores([]) |> add_underscores([])

  defp remove_underscores([?_ | rest], acc), do: remove_underscores(rest, acc)
  defp remove_underscores([digit | rest], acc), do: remove_underscores(rest, [digit | acc])
  defp remove_underscores([], reversed_list), do: reversed_list

  defp add_underscores([a, b, c, d | rest], acc), do: add_underscores([d | rest], [?_, c, b, a | acc])

  defp add_underscores(reversed_list, acc), do: reversed_list |> Enum.reverse(acc) |> to_string()

  # Check if the current node is inside a guard clause
  defp in_guard?(zipper) do
    in_guard?(zipper, false)
  end

  defp in_guard?(nil, found?), do: found?

  defp in_guard?(zipper, found?) do
    case Zipper.node(zipper) do
      # Function definition with guard
      {:def, _, [{:when, _, _} | _]} -> true
      {:defp, _, [{:when, _, _} | _]} -> true
      # Guard expression itself
      {:when, _, _} -> true
      # Abort the search upward when we hit the beginning of a block
      {{:__block__, _, [:do]}, _} -> false
      # Continue searching up the tree
      _ -> in_guard?(Zipper.up(zipper), found?)
    end
  end
end
