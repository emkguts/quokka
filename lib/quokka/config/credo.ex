# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Config.Credo do
  @moduledoc false

  alias Credo.Check.Design.AliasUsage
  alias Credo.Check.Readability.AliasOrder
  alias Credo.Check.Readability.BlockPipe
  alias Credo.Check.Readability.LargeNumbers
  alias Credo.Check.Readability.MaxLineLength
  alias Credo.Check.Readability.MultiAlias
  alias Credo.Check.Readability.OnePipePerLine
  alias Credo.Check.Readability.ParenthesesOnZeroArityDefs
  alias Credo.Check.Readability.SinglePipe
  alias Credo.Check.Readability.StrictModuleLayout
  alias Credo.Check.Refactor.CondStatements
  alias Credo.Check.Refactor.FilterFilter
  alias Credo.Check.Refactor.NegatedConditionsWithElse
  alias Credo.Check.Refactor.PipeChainStart
  alias Credo.Check.Refactor.UtcNowTruncate

  def extract() do
    checks()
    |> Enum.reduce(%{}, &apply_check/2)
  end

  defp checks() do
    case read_config().checks do
      checks when is_list(checks) -> checks
      checks -> Map.get(checks, :enabled, [])
    end
  end

  defp read_config() do
    exec = Credo.Execution.build()
    dir = File.cwd!()

    case Credo.ConfigFile.read_or_default(exec, dir) do
      {:ok, config} -> config
      {:error, _} -> %{checks: []}
    end
  end

  defp apply_check({AliasOrder, opts}, acc) when is_list(opts) do
    Map.put(acc, :sort_order, opts[:sort_method])
  end

  defp apply_check({AliasUsage, opts}, acc) when is_list(opts) do
    acc
    |> Map.put(:lift_alias, true)
    |> Map.put(:lift_alias_depth, opts[:if_nested_deeper_than])
    |> Map.put(:lift_alias_frequency, opts[:if_called_more_often_than])
    |> Map.put(:lift_alias_excluded_namespaces, opts[:excluded_namespaces])
    |> Map.put(:lift_alias_excluded_lastnames, opts[:excluded_lastnames])
    |> Map.put(:lift_alias_only, opts[:only])
  end

  defp apply_check({BlockPipe, opts}, acc) when is_list(opts) do
    acc
    |> Map.put(:block_pipe_flag, true)
    |> Map.put(:block_pipe_exclude, opts[:exclude])
  end

  defp apply_check({LargeNumbers, opts}, acc) when is_list(opts) do
    Map.put(acc, :large_numbers_gt, opts[:only_greater_than] || 9999)
  end

  defp apply_check({MaxLineLength, opts}, acc) when is_list(opts) do
    Map.put(acc, :line_length, opts[:max_length])
  end

  defp apply_check({MultiAlias, opts}, acc) when is_list(opts) do
    Map.put(acc, :rewrite_multi_alias, true)
  end

  defp apply_check({CondStatements, false}, acc) do
    Map.put(acc, :cond_statements, false)
  end

  defp apply_check({FilterFilter, opts}, acc) when is_list(opts) do
    Map.put(acc, :filter_filter, true)
  end

  defp apply_check({NegatedConditionsWithElse, false}, acc) do
    Map.put(acc, :negated_conditions_with_else, true)
  end

  defp apply_check({OnePipePerLine, opts}, acc) when is_list(opts) do
    Map.put(acc, :one_pipe_per_line, true)
  end

  defp apply_check({ParenthesesOnZeroArityDefs, opts}, acc) when is_list(opts) do
    Map.put(acc, :zero_arity_parens, opts[:parens] || false)
  end

  defp apply_check({PipeChainStart, opts}, acc) when is_list(opts) do
    acc
    |> Map.put(:pipe_chain_start_flag, true)
    |> Map.put(:pipe_chain_start_excluded_functions, opts[:excluded_functions])
    |> Map.put(:pipe_chain_start_excluded_argument_types, opts[:excluded_argument_types])
  end

  defp apply_check({SinglePipe, opts}, acc) when is_list(opts) do
    Map.put(acc, :single_pipe_flag, true)
  end

  defp apply_check({StrictModuleLayout, opts}, acc) when is_list(opts) do
    acc
    |> Map.put(:strict_module_layout_order, opts[:order])
    |> Map.put(:strict_module_layout_ignore, opts[:ignore] || [])
    |> Map.put(:strict_module_layout_ignored_module_attributes, opts[:ignore_module_attributes] || [])
  end

  defp apply_check({UtcNowTruncate, opts}, acc) when is_list(opts) do
    Map.put(acc, :utc_now_truncate, true)
  end

  defp apply_check(_, acc), do: acc
end
