# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.Configs do
  @moduledoc """
  Orders `Config.config/2,3` stanzas in configuration files.

  - ordering is done only within immediate-sibling config statements
  - assignments are moved above the configuration blocks
  - any non `config/2,3` or assignment (`=/2`) calls mark the end of a sorting block.
    this is support having conditional blocks (`if/case/cond`) and `import_config` stanzas between blocks

  ### Breakages

  If you configure the same values multiple times, Quokka may swap their orders

  **Before**

    line 04: config :foo, bar: :zab
    line 40: config :foo, bar: :baz

    # Application.fetch_env!(:foo)[:bar] => :baz

  **After**

    line 04: config :foo, bar: :baz
    line 05: config :foo, bar: :zab

    # Application.fetch_env!(:foo)[:bar] => :zab

  **Fix**

  The reason Quokka sorts configuration is to help you noticed these duplicated configuration stanzas.
  Delete the duplicative/erroneous stanza and life will be good.
  """

  alias Quokka.Style

  def run({{:import, _, [{:__aliases__, _, [:Config]}]}, _} = zipper, %{config?: true} = ctx) do
    {:skip, zipper, Map.put(ctx, :mix_config?, true)}
  end

  def run({{:config, cfm, [_, _ | _]} = config, zm}, %{mix_config?: true, comments: comments} = ctx) do
    # all of these list are reversed due to the reduce
    {configs, assignments, rest} = accumulate(zm.r, [], [])

    configs =
      [config | configs]
      |> Enum.group_by(fn
        {:config, _, [{:__block__, _, [app]} | _]} -> app
        {:config, _, [arg | _]} -> Style.without_meta(arg)
      end)
      |> Enum.sort()
      |> Enum.flat_map(fn {_app, configs} ->
        configs
        |> Enum.sort_by(&Style.without_meta/1)
        |> Style.reset_newlines()
      end)

    nodes =
      assignments
      |> Enum.reverse()
      |> Style.reset_newlines()
      |> Enum.concat(configs)

    block = [config | Enum.take(zm.r, length(zm.r) - length(rest))]

    {nodes, comments} =
      cond do
        not changed?(nodes) ->
          {nodes, comments}

        # Regions are split by line, which can't tell apart statements sharing a line (`config :b, 1; config :a, 1`)
        shares_lines?(block) ->
          {node_comments, _} = Style.comments_for_node(config, comments)
          first_line = min(List.last(node_comments)[:line] || cfm[:line], cfm[:line])
          Style.order_line_meta_and_comments(nodes, comments, first_line)

        true ->
          prev_last_line =
            case zm.l do
              [prev | _] -> last_line(prev)
              [] -> 0
            end

          {regions, comments} = comment_regions(block, comments, prev_last_line)
          {first_line, _, _} = regions[key(config)]
          place_nodes_and_comments(nodes, regions, comments, first_line)
      end

    [config | left_siblings] = Enum.reverse(nodes, zm.l)

    {:skip, {config, %{zm | l: left_siblings, r: rest}}, %{ctx | comments: comments}}
  end

  def run(zipper, %{config?: true} = ctx) do
    {:cont, zipper, ctx}
  end

  def run(zipper, %{file: file} = ctx) do
    if file =~ ~r|config/.*\.exs| or file =~ ~r|rel/overlays/.*\.exs| do
      # @TODO have this run forward to `import Config`, then run forward from there until we find `config` itself. no need for multi function head
      {:cont, zipper, Map.put(ctx, :config?, true)}
    else
      {:halt, zipper, ctx}
    end
  end

  defp changed?([{_, am, _}, {_, bm, _} = b | tail]) do
    if am[:line] > bm[:line], do: true, else: changed?([b | tail])
  end

  defp changed?(_), do: false

  # Splits the block's lines into one region per statement, so the statement's comments can move with it.
  # A region runs from the comment lines directly above its statement (no blank line between them) up to
  # the next statement's region. That covers comments within the statement, like those in a multi-line
  # keyword list, and any standalone comment block between it and the next statement.
  #
  # Uses line boundaries between statements rather than `Style.comments_for_lines/3`, which can claim
  # comments belonging to a neighbor. Comments outside the block (above its first statement's region,
  # or after its last statement) aren't owned and keep their lines.
  #
  # Returns a map of statement key => `{first_line, line_count, comments}`, plus the unowned comments.
  defp comment_regions(block, comments, prev_last_line) do
    {regions, comments, last_line} =
      Enum.reduce(block, {[], comments, prev_last_line}, fn node, {regions, comments, prev_last_line} ->
        line = Style.meta(node)[:line]
        last_line = last_line(node)
        {before, comments} = Enum.split_with(comments, &(&1.line > prev_last_line and &1.line < line))
        {inner, comments} = Enum.split_with(comments, &(&1.line >= line and &1.line <= last_line))
        {floating, leading} = split_leading_comments(before, line)

        {regions, comments} =
          case regions do
            [{key, first_line, owned} | regions] -> {[{key, first_line, owned ++ floating} | regions], comments}
            [] -> {regions, floating ++ comments}
          end

        first_line =
          case leading do
            [] -> line
            [%{line: first_line} | _] -> first_line
          end

        {[{key(node), first_line, leading ++ inner} | regions], comments, last_line}
      end)

    {regions, _} =
      Enum.reduce(regions, {%{}, last_line + 1}, fn {key, first_line, owned}, {regions, next_line} ->
        {Map.put(regions, key, {first_line, next_line - first_line, owned}), first_line}
      end)

    {regions, comments}
  end

  # `comments` are sorted by line; the leading comments are the run of consecutive lines ending just above `line`
  defp split_leading_comments(comments, line) do
    {leading, _} =
      comments
      |> Enum.reverse()
      |> Enum.reduce_while({[], line - 1}, fn
        %{line: expected} = comment, {leading, expected} -> {:cont, {[comment | leading], expected - 1}}
        _comment, leading_and_expected -> {:halt, leading_and_expected}
      end)

    {Enum.drop(comments, -length(leading)), leading}
  end

  # Lays out the sorted nodes' regions back to back from `start_line`. Shifting each region as a whole keeps
  # the line gaps the formatter uses to place blank lines around comments, and since the regions tile the
  # original block, the block still takes up the same lines.
  defp place_nodes_and_comments(nodes, regions, comments, start_line) do
    {nodes, {comments, _}} =
      Enum.map_reduce(nodes, {comments, start_line}, fn node, {comments, line} ->
        {first_line, line_count, owned} = regions[key(node)]
        delta = line - first_line
        owned = Enum.map(owned, &%{&1 | line: &1.line + delta})
        {Style.shift_line(node, delta), {owned ++ comments, line + line_count}}
      end)

    {nodes, Enum.sort_by(comments, & &1.line)}
  end

  defp shares_lines?(block) do
    block
    |> Enum.chunk_every(2, 1, :discard)
    |> Enum.any?(fn [a, b] -> Style.meta(b)[:line] <= last_line(a) end)
  end

  defp key(node), do: Style.meta(node)[:line]

  defp last_line(node), do: Style.meta(node)[:end_of_expression][:line] || Style.max_line(node)

  defp accumulate([{:config, _, [_, _ | _]} = c | siblings], cs, as), do: accumulate(siblings, [c | cs], as)

  defp accumulate([{:=, _, [_lhs, _rhs]} = a | siblings], cs, as), do: accumulate(siblings, cs, [a | as])

  defp accumulate(rest, configs, assignments), do: {configs, assignments, rest}
end
