# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style.Autosort do
  @moduledoc false

  @behaviour Quokka.Style

  alias Quokka.Style
  alias Quokka.Zipper

  def run(zipper, ctx) do
    autosort_types = Quokka.Config.autosort()

    if Enum.empty?(autosort_types) do
      {:skip, zipper, ctx}
    else
      skip_sort_lines = collect_skip_sort_lines(ctx.comments)

      node = Zipper.node(zipper)
      node_line = Style.meta(node)[:line]

      should_skip = node_line && MapSet.member?(skip_sort_lines, node_line)
      has_comments = has_comments_inside?(node, ctx.comments)
      is_sortable = get_node_type(node) in autosort_types
      is_query = ecto_from_query?(node)

      cond do
        is_query and Quokka.Config.autosort_exclude_ecto?() ->
          {:skip, zipper, ctx}

        should_skip || has_comments || !is_sortable ->
          {:cont, zipper, ctx}

        true ->
          {sorted, _} = sort(node, [])
          {:cont, Zipper.replace(zipper, sorted), ctx}
      end
    end
  end

  @doc false
  def sort(node, comments), do: do_sort(node, comments)

  defp ecto_from_query?(node) do
    case node do
      {{:., _, [{:__aliases__, _, [:Ecto, :Query]}, :from]}, _, _} ->
        true

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

  defp numeric_aware_sort(list) do
    {numeric_items, non_numeric_items} = Enum.split_with(list, &numeric_key?/1)

    sorted_numeric = Enum.sort_by(numeric_items, &extract_key/1)
    sorted_non_numeric = Enum.sort_by(non_numeric_items, &Macro.to_string/1)

    sorted_numeric ++ sorted_non_numeric
  end

  defp numeric_key?({{:__block__, _, [key]}, _}) when is_number(key), do: true
  defp numeric_key?({key, _}) when is_number(key), do: true
  defp numeric_key?({{:.., _, [{:__block__, _, [start]}, {:__block__, _, [_stop]}]}, _}) when is_number(start), do: true
  defp numeric_key?({{:.., _, [start, _stop]}, _}) when is_number(start), do: true
  defp numeric_key?(_), do: false

  defp extract_key({{:__block__, _, [key]}, _}), do: key
  defp extract_key({{:.., _, [{:__block__, _, [start]}, {:__block__, _, [_stop]}]}, _}), do: start
  defp extract_key({{:.., _, [start, _stop]}, _}), do: start
  defp extract_key({key, _}), do: key

  defp do_sort({parent, meta, [list]} = node, comments) when parent in ~w(defstruct __block__)a and is_list(list) do
    list = numeric_aware_sort(list)
    line = meta[:line]

    {list, comments} =
      if line == Style.max_line(node),
        do: {list, comments},
        else: Style.order_line_meta_and_comments(list, comments, line)

    {{parent, meta, [list]}, comments}
  end

  defp do_sort({:defstruct, meta, [{:__block__, _, [_]} = list]}, comments) do
    {list, comments} = do_sort(list, comments)
    {{:defstruct, meta, [list]}, comments}
  end

  defp do_sort({:%{}, meta, [{:|, _, [var, keyword_list]}]}, comments) do
    {{:__block__, meta, [keyword_list]}, comments} = do_sort({:__block__, meta, [keyword_list]}, comments)
    {{:%{}, meta, [{:|, meta, [var, keyword_list]}]}, comments}
  end

  defp do_sort({:%{}, meta, list}, comments) when is_list(list) do
    {{:__block__, meta, [list]}, comments} = do_sort({:__block__, meta, [list]}, comments)
    {{:%{}, meta, list}, comments}
  end

  defp do_sort({:%, m, [struct, map]}, comments) do
    {map, comments} = do_sort(map, comments)
    {{:%, m, [struct, map]}, comments}
  end

  defp do_sort({:sigil_w, sm, [{:<<>>, bm, [string]}, modifiers]}, comments) do
    {prepend, joiner, append} =
      case Regex.run(~r|^\s+|, string) do
        nil -> {"", " ", ""}
        [joiner] -> {joiner, joiner, ~r|\s+$| |> Regex.run(string) |> hd()}
      end

    string = string |> String.split() |> Enum.sort() |> Enum.join(joiner)
    {{:sigil_w, sm, [{:<<>>, bm, [prepend, string, append]}, modifiers]}, comments}
  end

  defp do_sort({:=, m, [lhs, rhs]}, comments) do
    {rhs, comments} = do_sort(rhs, comments)
    {{:=, m, [lhs, rhs]}, comments}
  end

  defp do_sort({:@, attr_meta, [{attr, annotation_meta, [{:"::", spec_meta, [lhs, rhs]}]}]}, comments)
       when attr in [:type, :typep] do
    {rhs, comments} = do_sort(rhs, comments)
    {{:@, attr_meta, [{attr, annotation_meta, [{:"::", spec_meta, [lhs, rhs]}]}]}, comments}
  end

  defp do_sort({:@, attr_meta, [{attr, annotation_meta, [assignment]}]}, comments) do
    {assignment, comments} = do_sort(assignment, comments)
    {{:@, attr_meta, [{attr, annotation_meta, [assignment]}]}, comments}
  end

  defp do_sort({:embedded_schema, meta, [[{{:__block__, _, [:do]}, {:__block__, block_meta, fields}}]]}, comments) do
    {sorted_fields, comments} = sort_schema_fields(fields, comments, meta[:line])
    {{:embedded_schema, meta, [[{{:__block__, [], [:do]}, {:__block__, block_meta, sorted_fields}}]]}, comments}
  end

  defp do_sort(
         {schema_type, meta, [table_name, [{{:__block__, _, [:do]}, {:__block__, block_meta, fields}}]]},
         comments
       )
       when schema_type in [:schema, :typed_schema] do
    {sorted_fields, comments} = sort_schema_fields(fields, comments, meta[:line])
    {{schema_type, meta, [table_name, [{{:__block__, [], [:do]}, {:__block__, block_meta, sorted_fields}}]]}, comments}
  end

  defp do_sort({key, value}, comments) do
    {value, comments} = do_sort(value, comments)
    {{key, value}, comments}
  end

  defp do_sort({f, m, args} = node, comments) do
    if m[:do] && m[:end] && match?([{{:__block__, _, [:do]}, {:__block__, _, _}}], List.last(args)) do
      {[{{:__block__, m1, [:do]}, {:__block__, m2, nodes}}], args} = List.pop_at(args, -1)

      {nodes, comments} =
        nodes
        |> numeric_aware_sort()
        |> Style.order_line_meta_and_comments(comments, m[:line])

      args = List.insert_at(args, -1, [{{:__block__, m1, [:do]}, {:__block__, m2, nodes}}])

      {{f, m, args}, comments}
    else
      {node, comments}
    end
  end

  defp do_sort(x, comments), do: {x, comments}

  defp sort_schema_fields(fields, comments, meta_line) do
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
        grouped_fields |> Map.get(type, []) |> numeric_aware_sort()
      end)
      |> Enum.reject(&(&1 == []))

    other_fields =
      grouped_fields
      |> Map.drop(field_type_order)
      |> Map.values()
      |> List.flatten()
      |> numeric_aware_sort()

    sorted_fields =
      if Enum.empty?(sorted_groups) do
        other_fields
      else
        sorted_groups
        |> Enum.map(&Style.reset_newlines/1)
        |> Enum.reduce(fn group, acc ->
          acc ++ Style.reset_newlines(group)
        end)
        |> Kernel.++(other_fields)
      end

    Style.order_line_meta_and_comments(sorted_fields, comments, meta_line)
  end
end
