# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.CommentDirectives do
  @moduledoc """
  Leave a comment for Quokka asking it to maintain code in a certain way.

  `# quokka:sort` maintains sorting of wordlists (by string comparison) and lists (string comparison of code representation)
  """

  @behaviour Quokka.Style

  alias Quokka.Style
  alias Quokka.Zipper

  def run(zipper, ctx) do
    {zipper, comments} =
      ctx.comments
      |> Enum.filter(&(&1.text == "# quokka:sort"))
      |> Enum.map(& &1.line)
      |> Enum.reduce({zipper, ctx.comments}, fn line, {zipper, comments} ->
        found = Zipper.find(zipper, &(line + 1 == Style.meta(&1)[:line]))

        if found do
          {sorted, comments} = found |> Zipper.node() |> sort(comments)
          {Zipper.replace(found, sorted), comments}
        else
          {zipper, comments}
        end
      end)

    autosort_types = Quokka.Config.autosort()

    if Enum.empty?(autosort_types) do
      {:skip, zipper, %{ctx | comments: comments}}
    else
      skip_sort_lines = collect_skip_sort_lines(ctx.comments)

      node = Zipper.node(zipper)
      node_line = Style.meta(node)[:line]

      should_skip = node_line && MapSet.member?(skip_sort_lines, node_line)
      has_comments = has_comments_inside?(node, ctx.comments)
      is_sortable = get_node_type(node) in autosort_types
      is_query = is_ecto_from_query?(node)

      cond do
        is_query and Quokka.Config.autosort_exclude_ecto?() ->
          {:skip, zipper, %{ctx | comments: comments}}

        should_skip || has_comments || !is_sortable ->
          {:cont, zipper, %{ctx | comments: comments}}

        true ->
          {sorted, _} = sort(node, [])
          {:cont, Zipper.replace(zipper, sorted), %{ctx | comments: comments}}
      end
    end
  end

  defp is_ecto_from_query?(node) do
    case node do
      # Matches the remote call: `Ecto.Query.from(...)`
      {{:., _, [{:__aliases__, _, [:Ecto, :Query]}, :from]}, _, _} ->
        true

      # Matches the local call `from ...` and checks for the `in` expression
      # to ensure it's likely an Ecto query.
      {:from, _, [{:in, _, _} | _]} ->
        true

      _ ->
        false
    end
  end

  defp collect_skip_sort_lines(comments) do
    comments
    |> Enum.filter(&(&1.text == "# quokka:skip-sort"))
    |> Enum.reduce(MapSet.new(), fn comment, lines ->
      lines |> MapSet.put(comment.line) |> MapSet.put(comment.line + 1)
    end)
  end

  defp get_node_type(node) do
    case node do
      {schema, _, [_, [{{:__block__, _, [:do]}, _}]]} when schema in [:schema, :typed_schema] -> :schema
      {:embedded_schema, _, [[{{:__block__, _, [:do]}, _}]]} -> :schema
      {:%{}, _, _} -> :map
      {:%, _, [_, {:%{}, _, _}]} -> :map
      {:defstruct, _, _} -> :defstruct
      _ -> nil
    end
  end

  defp has_comments_inside?(node, comments) do
    start_line = Style.meta(node)[:line] || 0
    end_line = Style.max_line(node) || start_line

    end_line > start_line && Enum.any?(comments, &(&1.line > start_line && &1.line < end_line))
  end

  # defstruct with a syntax-sugared keyword list hits here
  defp sort({parent, meta, [list]} = node, comments) when parent in ~w(defstruct __block__)a and is_list(list) do
    list = Enum.sort_by(list, &Macro.to_string/1)
    line = meta[:line]
    # no need to fix line numbers if it's a single line structure
    {list, comments} =
      if line == Style.max_line(node),
        do: {list, comments},
        else: Style.order_line_meta_and_comments(list, comments, line)

    {{parent, meta, [list]}, comments}
  end

  # defstruct with a literal list
  defp sort({:defstruct, meta, [{:__block__, _, [_]} = list]}, comments) do
    {list, comments} = sort(list, comments)
    {{:defstruct, meta, [list]}, comments}
  end

  # map update with a keyword list
  defp sort({:%{}, meta, [{:|, _, [var, keyword_list]}]}, comments) do
    {{:__block__, meta, [keyword_list]}, comments} = sort({:__block__, meta, [keyword_list]}, comments)
    {{:%{}, meta, [{:|, meta, [var, keyword_list]}]}, comments}
  end

  # map
  defp sort({:%{}, meta, list}, comments) when is_list(list) do
    {{:__block__, meta, [list]}, comments} = sort({:__block__, meta, [list]}, comments)
    {{:%{}, meta, list}, comments}
  end

  # struct map
  defp sort({:%, m, [struct, map]}, comments) do
    {map, comments} = sort(map, comments)
    {{:%, m, [struct, map]}, comments}
  end

  defp sort({:sigil_w, sm, [{:<<>>, bm, [string]}, modifiers]}, comments) do
    # ew. gotta be a better way.
    # this keeps indentation for the sigil via joiner, while prepend and append are the bookending whitespace
    {prepend, joiner, append} =
      case Regex.run(~r|^\s+|, string) do
        # oneliner like `~w|c a b|`
        nil -> {"", " ", ""}
        # multiline like
        # `"\n  a\n  list\n  long\n  of\n  static\n  values\n"`
        #   ^^^^ `prepend`       ^^^^ `joiner`             ^^ `append`
        # note that joiner and prepend are the same in a multiline (unsure if this is always true)
        # @TODO: get all 3 in one pass of a regex. probably have to turn off greedy or something...
        [joiner] -> {joiner, joiner, ~r|\s+$| |> Regex.run(string) |> hd()}
      end

    string = string |> String.split() |> Enum.sort() |> Enum.join(joiner)
    {{:sigil_w, sm, [{:<<>>, bm, [prepend, string, append]}, modifiers]}, comments}
  end

  defp sort({:=, m, [lhs, rhs]}, comments) do
    {rhs, comments} = sort(rhs, comments)
    {{:=, m, [lhs, rhs]}, comments}
  end

  defp sort({:@, m, [{a, am, [assignment]}]}, comments) do
    {assignment, comments} = sort(assignment, comments)
    {{:@, m, [{a, am, [assignment]}]}, comments}
  end

  defp sort({schema_type, meta, [table_name, [{{:__block__, _, [:do]}, {:__block__, block_meta, fields}}]]}, comments)
       when schema_type in [:schema, :typed_schema, :embedded_schema] do
    field_type_order = Quokka.Config.autosort_schema_order()

    grouped_fields =
      fields
      |> Enum.group_by(fn
        {field_type, _, _}
        when field_type in [
               :belongs_to,
               :embeds_many,
               :embeds_one,
               :has_many,
               :has_one,
               :many_to_many,
               :field
             ] ->
          field_type

        other ->
          other
      end)

    sorted_groups =
      field_type_order
      |> Enum.map(fn type ->
        grouped_fields |> Map.get(type, []) |> Enum.sort_by(&Macro.to_string/1)
      end)
      |> Enum.reject(&(&1 == []))

    other_fields =
      grouped_fields
      |> Map.drop(field_type_order)
      |> Map.values()
      |> List.flatten()
      |> Enum.sort_by(&Macro.to_string/1)

    sorted_fields =
      sorted_groups
      |> Enum.map(&Style.reset_newlines/1)
      |> Enum.reduce(fn group, acc ->
        acc ++ Style.reset_newlines(group)
      end)
      |> Kernel.++(other_fields)

    {sorted_fields, comments} = Style.order_line_meta_and_comments(sorted_fields, comments, meta[:line])

    {{schema_type, meta, [table_name, [{{:__block__, [], [:do]}, {:__block__, block_meta, sorted_fields}}]]}, comments}
  end

  defp sort({key, value}, comments) do
    {value, comments} = sort(value, comments)
    {{key, value}, comments}
  end

  # sorts arbitrary ast nodes within a `do end` list
  defp sort({f, m, args} = node, comments) do
    if m[:do] && m[:end] && match?([{{:__block__, _, [:do]}, {:__block__, _, _}}], List.last(args)) do
      {[{{:__block__, m1, [:do]}, {:__block__, m2, nodes}}], args} = List.pop_at(args, -1)

      {nodes, comments} =
        nodes
        |> Enum.sort_by(&Macro.to_string/1)
        |> Style.order_line_meta_and_comments(comments, m[:line])

      args = List.insert_at(args, -1, [{{:__block__, m1, [:do]}, {:__block__, m2, nodes}}])

      {{f, m, args}, comments}
    else
      {node, comments}
    end
  end

  defp sort(x, comments), do: {x, comments}
end
