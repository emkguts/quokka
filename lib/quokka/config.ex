# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Config do
  @moduledoc false

  alias Credo.Check.Design.AliasUsage
  alias Credo.Check.Readability.AliasOrder
  alias Credo.Check.Readability.BlockPipe
  alias Credo.Check.Readability.LargeNumbers
  alias Credo.Check.Readability.MaxLineLength
  alias Credo.Check.Readability.MultiAlias
  alias Credo.Check.Readability.ParenthesesOnZeroArityDefs
  alias Credo.Check.Readability.SinglePipe
  alias Credo.Check.Readability.StrictModuleLayout
  alias Credo.Check.Refactor.PipeChainStart
  alias Quokka.Style.Blocks
  alias Quokka.Style.CommentDirectives
  alias Quokka.Style.Configs
  alias Quokka.Style.Defs
  alias Quokka.Style.Deprecations
  alias Quokka.Style.ModuleDirectives
  alias Quokka.Style.Pipes
  alias Quokka.Style.SingleNode

  @key __MODULE__

  # quokka:sort
  @styles_by_atom %{
    blocks: Blocks,
    comment_directives: CommentDirectives,
    configs: Configs,
    defs: Defs,
    deprecations: Deprecations,
    module_directives: ModuleDirectives,
    pipes: Pipes,
    single_node: SingleNode
  }

  @stdlib ~w(
    Access Agent Application Atom Base Behaviour Bitwise Code Date DateTime Dict Ecto Enum Exception
    File Float GenEvent GenServer HashDict HashSet Integer IO Kernel Keyword List
    Macro Map MapSet Module NaiveDateTime Node Oban OptionParser Path Port Process Protocol
    Range Record Regex Registry Set Stream String StringIO Supervisor System Task Time Tuple URI Version
  )a

  def set(config) do
    :persistent_term.get(@key)
    :ok
  rescue
    ArgumentError -> set!(config)
  end

  def set!(config \\ []) do
    credo_opts = extract_configs_from_credo()

    lift_alias_excluded_namespaces =
      Enum.map(credo_opts[:lift_alias_excluded_namespaces] || [], &Atom.to_string/1)

    lift_alias_excluded_lastnames =
      Enum.map(credo_opts[:lift_alias_excluded_lastnames] || [], &Atom.to_string/1)

    default_order = [:shortdoc, :moduledoc, :behaviour, :use, :import, :alias, :require]
    strict_module_layout_order = credo_opts[:strict_module_layout_order] || default_order

    :persistent_term.put(
      @key,
      # quokka:sort
      %{
        block_pipe_exclude: credo_opts[:block_pipe_exclude] || [],
        block_pipe_flag: credo_opts[:block_pipe_flag] || false,
        directories_excluded: Map.get(config[:files] || %{}, :excluded, []),
        directories_included: Map.get(config[:files] || %{}, :included, []),
        exclude_styles: config[:exclude] || [],
        inefficient_function_rewrites: Keyword.get(config, :inefficient_function_rewrites, true),
        large_numbers_gt: credo_opts[:large_numbers_gt] || :infinity,
        lift_alias: credo_opts[:lift_alias] || false,
        lift_alias_depth: credo_opts[:lift_alias_depth] || 0,
        lift_alias_excluded_lastnames: MapSet.new(lift_alias_excluded_lastnames ++ @stdlib),
        lift_alias_excluded_namespaces: MapSet.new(lift_alias_excluded_namespaces ++ @stdlib),
        lift_alias_frequency: credo_opts[:lift_alias_frequency] || 0,
        line_length: credo_opts[:line_length] || 98,
        only_styles: config[:only] || [],
        pipe_chain_start_excluded_argument_types: credo_opts[:pipe_chain_start_excluded_argument_types] || [],
        pipe_chain_start_excluded_functions: credo_opts[:pipe_chain_start_excluded_functions] || [],
        pipe_chain_start_flag: credo_opts[:pipe_chain_start_flag] || false,
        rewrite_multi_alias: credo_opts[:rewrite_multi_alias] || false,
        single_pipe_flag: credo_opts[:single_pipe_flag] || false,
        sort_order: credo_opts[:sort_order] || :alpha,
        strict_module_layout_order: strict_module_layout_order ++ (default_order -- strict_module_layout_order),
        zero_arity_parens: credo_opts[:zero_arity_parens] || false
      }
    )
  end

  def set_for_test!(key, value) do
    current_vals = :persistent_term.get(@key, %{})
    :persistent_term.put(@key, Map.put(current_vals, key, value))
  end

  def get(key) do
    @key
    |> :persistent_term.get()
    |> Map.fetch!(key)
  end

  def get_styles() do
    styles_to_apply =
      cond do
        :line_length in only_styles() ->
          []

        only_styles() == [] ->
          Map.values(@styles_by_atom)

        true ->
          Enum.map(only_styles(), &@styles_by_atom[&1])
          |> Enum.reject(&is_nil/1)
      end

    styles_to_exclude = Enum.map(exclude_styles(), &@styles_by_atom[&1])
    Enum.filter(styles_to_apply, fn style -> !Enum.member?(styles_to_exclude, style) end)
  end

  def only_styles() do
    get(:only_styles)
  end

  def exclude_styles() do
    get(:exclude_styles)
  end

  def sort_order() do
    get(:sort_order)
  end

  def block_pipe_flag?() do
    get(:block_pipe_flag)
  end

  def block_pipe_exclude() do
    get(:block_pipe_exclude)
  end

  def inefficient_function_rewrites?() do
    get(:inefficient_function_rewrites)
  end

  def large_numbers_gt() do
    get(:large_numbers_gt)
  end

  def lift_alias?() do
    get(:lift_alias)
  end

  def lift_alias_depth() do
    get(:lift_alias_depth)
  end

  def lift_alias_excluded_lastnames() do
    get(:lift_alias_excluded_lastnames)
  end

  def lift_alias_excluded_namespaces() do
    get(:lift_alias_excluded_namespaces)
  end

  def lift_alias_frequency() do
    get(:lift_alias_frequency)
  end

  def line_length() do
    get(:line_length)
  end

  def pipe_chain_start_excluded_functions() do
    get(:pipe_chain_start_excluded_functions)
  end

  def pipe_chain_start_excluded_argument_types() do
    get(:pipe_chain_start_excluded_argument_types)
  end

  def refactor_pipe_chain_starts?() do
    get(:pipe_chain_start_flag)
  end

  def rewrite_multi_alias?() do
    get(:rewrite_multi_alias)
  end

  def single_pipe_flag?() do
    get(:single_pipe_flag)
  end

  def strict_module_layout_order() do
    get(:strict_module_layout_order)
  end

  def zero_arity_parens?() do
    get(:zero_arity_parens)
  end

  def allowed_directory?(file) do
    relative_path = Path.relative_to_cwd(file)
    included_dirs = get(:directories_included)
    excluded_dirs = get(:directories_excluded)

    cond do
      Enum.any?(excluded_dirs, &String.starts_with?(relative_path, &1)) -> false
      Enum.empty?(included_dirs) -> true
      true -> Enum.any?(included_dirs, &String.starts_with?(relative_path, &1))
    end
  end

  defp read_credo_config() do
    exec = Credo.Execution.build()
    dir = File.cwd!()
    {:ok, config} = Credo.ConfigFile.read_or_default(exec, dir)
    config
  end

  defp extract_configs_from_credo() do
    case read_credo_config().checks do
      checks when is_list(checks) -> checks
      checks -> Map.get(checks, :enabled, [])
    end
    |> Enum.reduce(%{}, fn
      {AliasOrder, opts}, acc when is_list(opts) ->
        Map.put(acc, :sort_order, opts[:sort_method])

      {AliasUsage, opts}, acc when is_list(opts) ->
        acc
        |> Map.put(:lift_alias, true)
        |> Map.put(:lift_alias_depth, opts[:if_nested_deeper_than])
        |> Map.put(:lift_alias_frequency, opts[:if_called_more_often_than])
        |> Map.put(:lift_alias_excluded_namespaces, opts[:excluded_namespaces])
        |> Map.put(:lift_alias_excluded_lastnames, opts[:excluded_lastnames])

      {BlockPipe, opts}, acc when is_list(opts) ->
        acc
        |> Map.put(:block_pipe_flag, true)
        |> Map.put(:block_pipe_exclude, opts[:exclude])

      {LargeNumbers, opts}, acc when is_list(opts) ->
        acc
        |> Map.put(:large_numbers_gt, opts[:only_greater_than] || 9999)

      {MaxLineLength, opts}, acc when is_list(opts) ->
        Map.put(acc, :line_length, opts[:max_length])

      {MultiAlias, opts}, acc when is_list(opts) ->
        Map.put(acc, :rewrite_multi_alias, true)

      {ParenthesesOnZeroArityDefs, opts}, acc when is_list(opts) ->
        Map.put(acc, :zero_arity_parens, opts[:parens] || false)

      {PipeChainStart, opts}, acc when is_list(opts) ->
        acc
        |> Map.put(:pipe_chain_start_flag, true)
        |> Map.put(:pipe_chain_start_excluded_functions, opts[:excluded_functions])
        |> Map.put(:pipe_chain_start_excluded_argument_types, opts[:excluded_argument_types])

      {SinglePipe, opts}, acc when is_list(opts) ->
        Map.put(acc, :single_pipe_flag, true)

      {StrictModuleLayout, opts}, acc when is_list(opts) ->
        Map.put(acc, :strict_module_layout_order, opts[:order])

      _, acc ->
        acc
    end)
  end
end
