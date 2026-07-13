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

  alias Quokka.Config.Credo
  alias Quokka.Config.Plugins
  alias Quokka.Style.Autosort
  alias Quokka.Style.Blocks
  alias Quokka.Style.CommentDirectives
  alias Quokka.Style.Configs
  alias Quokka.Style.Defs
  alias Quokka.Style.Deprecations
  alias Quokka.Style.ModuleDirectives
  alias Quokka.Style.Pipes
  alias Quokka.Style.SingleNode
  alias Quokka.Style.Tests

  require Logger

  @key __MODULE__

  # quokka:sort
  @styles_by_atom %{
    autosort: Autosort,
    blocks: Blocks,
    configs: Configs,
    defs: Defs,
    deprecations: Deprecations,
    module_directives: ModuleDirectives,
    pipes: Pipes,
    single_node: SingleNode,
    tests: Tests
  }

  # CommentDirectives is not configurable; # quokka:sort always runs.
  @style_pipeline [
    Blocks,
    CommentDirectives,
    Autosort,
    Configs,
    Defs,
    Deprecations,
    ModuleDirectives,
    Pipes,
    SingleNode,
    Tests
  ]

  @stdlib ~w(
    Access Agent Application Atom Base Behaviour Bitwise Code Date DateTime Dict Ecto Enum Exception
    File Float GenEvent GenServer HashDict HashSet Integer IO Kernel Keyword List
    Macro Map MapSet Mix Module NaiveDateTime Node Oban OptionParser Path Port Process Protocol
    Range Record Regex Registry Set Stream String StringIO Supervisor System Task Time Tuple URI Version
  )a

  @default_schema_order [
    :field,
    :belongs_to,
    :has_many,
    :has_one,
    :many_to_many,
    :embeds_many,
    :embeds_one
  ]

  @default_strict_module_layout_order [:shortdoc, :moduledoc, :behaviour, :use, :import, :alias, :require]

  @config_getters ~w(
    autosort autosort_schema_order block_pipe_exclude elixir_version exclude_styles
    large_numbers_gt lift_alias_depth lift_alias_excluded_lastnames lift_alias_excluded_namespaces
    lift_alias_frequency lift_alias_only line_length only_styles piped_function_exclusions
    pipe_chain_start_excluded_argument_types plugins plugin_opts sort_order
    strict_module_layout_ignore strict_module_layout_ignored_module_attributes strict_module_layout_order
  )a

  @config_boolean_getters ~w(
    autosort_exclude_ecto block_pipe_flag cond_statements exclude_nums_with_underscores
    inefficient_function_rewrites lift_alias negated_conditions_with_else one_pipe_per_line
    pipe_into_case refactor_pipe_chain_starts rewrite_multi_alias single_pipe_flag utc_now_truncate
    zero_arity_parens
  )a

  for key <- @config_getters do
    def unquote(key)(), do: get(unquote(key))
  end

  for key <- @config_boolean_getters do
    def unquote(:"#{key}?")(), do: get(unquote(key))
  end

  def set(formatter_opts) do
    :persistent_term.get(@key)
    :ok
  rescue
    ArgumentError -> set!(formatter_opts)
  end

  def set!(formatter_opts) do
    quokka = formatter_opts[:quokka] || []
    credo = Credo.extract()
    {plugins, plugin_opts} = Plugins.load(quokka)
    exclude = Keyword.get(quokka, :exclude, [])

    :persistent_term.put(@key, build_config_map(formatter_opts, quokka, credo, exclude, plugins, plugin_opts))
    :ok
  end

  def get(key) do
    @key
    |> :persistent_term.get()
    |> Map.fetch!(key)
  end

  def get_styles() do
    enabled_styles =
      cond do
        :line_length in only_styles() ->
          MapSet.new()

        only_styles() == [] ->
          MapSet.new(Map.values(@styles_by_atom))

        true ->
          only_styles()
          |> Enum.map(&@styles_by_atom[&1])
          |> Enum.reject(&is_nil/1)
          |> MapSet.new()
      end

    excluded_styles =
      exclude_styles()
      |> Enum.reject(&(&1 == :comment_directives))
      |> Enum.map(&@styles_by_atom[&1])
      |> Enum.reject(&is_nil/1)
      |> MapSet.new()

    builtin_styles =
      Enum.filter(@style_pipeline, fn
        CommentDirectives ->
          true

        style ->
          MapSet.member?(enabled_styles, style) and not MapSet.member?(excluded_styles, style)
      end)

    # Plugins run after built-in styles, in declaration order
    builtin_styles ++ (plugins() || [])
  end

  def pipe_chain_start_excluded_functions() do
    case get(:pipe_chain_start_excluded_functions) do
      [_ | _] = list ->
        list

      empty when empty in [nil, []] ->
        # :piped_function_exclusions are provided as atoms, rather than strings,
        # but the Credo config expects strings.
        Enum.map(piped_function_exclusions(), &to_string/1)
    end
  end

  def plugin_opts(module) do
    plugin_opts()[module] || []
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

  defp build_config_map(formatter_opts, quokka, credo, exclude, plugins, plugin_opts) do
    {autosort, autosort_schema_order} = parse_autosort(quokka)
    {inefficient_function_rewrites, piped_function_exclusions} = parse_deprecated_opts(quokka, exclude)

    warn_comment_directives_config(quokka)

    # quokka:sort
    %{
      autosort: autosort,
      autosort_exclude_ecto: :autosort_ecto in exclude,
      autosort_schema_order: autosort_schema_order,
      directories_excluded: Map.get(quokka[:files] || %{}, :excluded, []),
      directories_included: Map.get(quokka[:files] || %{}, :included, []),
      elixir_version: parse_elixir_version(quokka[:elixir_version]),
      exclude_nums_with_underscores: :nums_with_underscores in exclude,
      exclude_styles: exclude,
      inefficient_function_rewrites: inefficient_function_rewrites,
      only_styles: quokka[:only] || [],
      pipe_into_case: :pipe_into_case not in exclude,
      piped_function_exclusions: piped_function_exclusions,
      plugin_opts: plugin_opts,
      plugins: plugins
    }
    |> Map.merge(credo_settings(credo, formatter_opts))
  end

  defp parse_autosort(quokka) do
    autosort = quokka[:autosort] || []

    schema_order =
      autosort
      |> Keyword.get(:schema, [])
      |> then(&(&1 ++ (@default_schema_order -- &1)))

    normalized =
      Enum.map(autosort, fn
        {:schema, _order} -> :schema
        other -> other
      end)

    {normalized, schema_order}
  end

  defp parse_deprecated_opts(quokka, exclude) do
    inefficient_function_rewrites =
      case Keyword.get(quokka, :inefficient_function_rewrites) do
        nil ->
          :inefficient_functions not in exclude

        value ->
          Logger.warning("inefficient_function_rewrites is deprecated. Use exclude: [:inefficient_functions] instead.")
          value
      end

    piped_function_exclusions =
      case Keyword.get(quokka, :piped_function_exclusions) do
        nil ->
          Keyword.get(exclude, :piped_functions, [])

        exclusions ->
          Logger.warning(
            "piped_function_exclusions is deprecated. Use exclude: [piped_functions: [:fun1, :fun2, ...]] instead."
          )

          exclusions
      end

    {inefficient_function_rewrites, piped_function_exclusions}
  end

  defp warn_comment_directives_config(quokka) do
    only = quokka[:only] || []
    exclude = quokka[:exclude] || []

    if :comment_directives in only do
      Logger.warning(
        ":comment_directives in :only has no effect; use :autosort for config-driven sorting. # quokka:sort always runs."
      )
    end

    if :comment_directives in exclude do
      Logger.warning("exclude: [:comment_directives] has no effect; # quokka:sort always runs")
    end
  end

  defp credo_settings(credo, formatter_opts) do
    %{
      block_pipe_exclude: credo[:block_pipe_exclude] || [],
      block_pipe_flag: credo[:block_pipe_flag] || false,
      cond_statements: Map.get(credo, :cond_statements, true),
      large_numbers_gt: credo[:large_numbers_gt] || :infinity,
      line_length: min(credo[:line_length], formatter_opts[:line_length]) || 98,
      negated_conditions_with_else: Map.get(credo, :negated_conditions_with_else, true),
      one_pipe_per_line: credo[:one_pipe_per_line] || false,
      pipe_chain_start_excluded_argument_types: credo[:pipe_chain_start_excluded_argument_types] || [],
      pipe_chain_start_excluded_functions: credo[:pipe_chain_start_excluded_functions] || [],
      refactor_pipe_chain_starts: credo[:pipe_chain_start_flag] || false,
      rewrite_multi_alias: credo[:rewrite_multi_alias] || false,
      single_pipe_flag: credo[:single_pipe_flag] || false,
      sort_order: credo[:sort_order] || :alpha,
      utc_now_truncate: credo[:utc_now_truncate] || false,
      zero_arity_parens: credo[:zero_arity_parens] || false
    }
    |> Map.merge(lift_alias_settings(credo))
    |> Map.merge(strict_module_layout_settings(credo))
  end

  defp lift_alias_settings(credo) do
    excluded_lastnames = credo[:lift_alias_excluded_lastnames] || []
    excluded_namespaces = credo[:lift_alias_excluded_namespaces] || []

    %{
      lift_alias: credo[:lift_alias] || false,
      lift_alias_depth: credo[:lift_alias_depth] || 0,
      lift_alias_excluded_lastnames: MapSet.new(Enum.map(excluded_lastnames, &String.to_atom/1) ++ @stdlib),
      lift_alias_excluded_namespaces: MapSet.new(Enum.map(excluded_namespaces, &String.to_atom/1) ++ @stdlib),
      lift_alias_frequency: credo[:lift_alias_frequency] || 0,
      lift_alias_only: credo[:lift_alias_only]
    }
  end

  defp strict_module_layout_settings(credo) do
    order = credo[:strict_module_layout_order] || @default_strict_module_layout_order

    %{
      strict_module_layout_ignore: credo[:strict_module_layout_ignore] || [],
      strict_module_layout_ignored_module_attributes: credo[:strict_module_layout_ignored_module_attributes] || [],
      strict_module_layout_order: order ++ (@default_strict_module_layout_order -- order)
    }
  end

  defp parse_elixir_version(nil) do
    System.version()
  end

  defp parse_elixir_version(configured_version) do
    case Regex.run(~r/(?:==|>=|>|~>)?\s*(\d+(?:\.\d+(?:\.\d+(?:-\w+)?)?)?)\b/, configured_version) do
      [_, version] ->
        case String.split(version, ".") do
          [major] -> "#{major}.0.0"
          [major, minor] -> "#{major}.#{minor}.0"
          [major, minor, patch] -> "#{major}.#{minor}.#{patch}"
        end

      _ ->
        System.version()
    end
  end
end
