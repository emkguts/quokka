# Copyright 2024 Adobe. All rights reserved.
# Copyright 2025 SmartRent. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Quokka.Style do
  @moduledoc """
  A Style takes AST and returns a transformed version of that AST.

  Because these transformations involve traversing trees (the "T" in "AST"), we wrap the AST in a structure
  called a Zipper to facilitate walking the trees.
  """

  alias Quokka.Zipper

  @type context :: %{
          comments: [map()],
          file: :stdin | String.t(),
          plugin_opts: keyword()
        }

  @doc """
  `run` will be used with `Zipper.traverse_while/3`, meaning it will be executed on every node of the AST.

  You can skip traversing parts of the tree by returning a Zipper that's further along in the traversal, for example
  by calling `Zipper.skip(zipper)` to skip an entire subtree you know is of no interest to your Style.
  """
  @callback run(Zipper.t(), context()) :: {Zipper.command(), Zipper.t(), context()}

  @doc "Recursively sets `:line` meta to `line`. Deletes `:newlines` unless `delete_lines: false` is passed"
  def set_line(ast_node, line, opts \\ []) do
    set_line = fn _ -> line end

    if Keyword.get(opts, :delete_newlines, true) do
      update_all_meta(ast_node, &(&1 |> update_line(set_line) |> Keyword.delete(:newlines)))
    else
      update_all_meta(ast_node, &update_line(&1, set_line))
    end
  end

  @doc "Recursively updates `:line` meta by adding `delta`"
  def shift_line(ast_node, delta) do
    shift_line = &(&1 + delta)
    update_all_meta(ast_node, &update_line(&1, shift_line))
  end

  defp update_line(meta, fun) do
    Enum.map(meta, fn
      {:line, line} -> {:line, fun.(line)}
      {k, v} when is_list(v) -> {k, update_line(v, fun)}
      kv -> kv
    end)
  end

  @doc "Traverses an ast node, updating all nodes' meta with `meta_fun`"
  def update_all_meta(node, meta_fun), do: Macro.prewalk(node, &Macro.update_meta(&1, meta_fun))

  @doc "prewalks ast and sets all meta to `nil`. useful for comparing AST without meta (line numbers, etc) interfering"
  def without_meta(ast), do: update_all_meta(ast, fn _ -> nil end)

  @doc """
  Returns the current node (wrapped in a `__block__` if necessary) if it's a valid place to insert additional nodes
  """
  @spec ensure_block_parent(Zipper.t()) :: {:ok, Zipper.t()} | :error
  def ensure_block_parent(zipper) do
    valid_block_location? =
      case Zipper.up(zipper) do
        {{:__block__, _, _}, _} -> true
        {{:->, _, _}, _} -> true
        {{_, _}, _} -> true
        nil -> true
        _ -> false
      end

    if valid_block_location? do
      {:ok, find_nearest_block(zipper)}
    else
      :error
    end
  end

  def do_block?([{{:__block__, _, [:do]}, _body} | _]), do: true
  def do_block?(_), do: false

  @doc """
  Returns a zipper focused on the nearest node where additional nodes can be inserted (a "block").

  The nearest node is either the current node, an ancestor, or one of those two but wrapped in a new `:__block__` node.
  """
  @spec find_nearest_block(Zipper.t()) :: Zipper.t()
  def find_nearest_block(zipper) do
    case Zipper.up(zipper) do
      # parent is a block!
      {{:__block__, _, _}, _} -> zipper
      # when a statement is an only child, it doesn't get a block wrapper
      # only child of a right arrow
      {{:->, _, _}, _} -> wrap_in_block(zipper)
      # only child of a `do` block
      {{_, _}, _} -> wrap_in_block(zipper)
      # one line snippet
      nil -> wrap_in_block(zipper)
      # we're in a pipe, assignment, function call, etc. gotta keep going up looking for a block
      parent -> find_nearest_block(parent)
    end
  end

  # give it a block parent, then step back to the child - we can insert next to it now that it's in a block
  defp wrap_in_block(zipper) do
    zipper
    |> Zipper.update(fn {_, meta, _} = node ->
      {:__block__, Keyword.take(meta, [:line]), [node]}
    end)
    |> Zipper.down()
  end

  @doc """
  Set the line of all comments with `line` in `range_start..range_end` to instead have line `range_start`
  """
  def displace_comments(comments, range) do
    Enum.map(comments, fn comment ->
      if comment.line in range do
        %{comment | line: range.first}
      else
        comment
      end
    end)
  end

  @doc """
  Change the `line` of all comments with `line` in `range` by adding `delta` to it.
  A positive delta will move the lines further down a file, while a negative delta will move them up.
  """
  def shift_comments(comments, range, delta) do
    shift_comments(comments, [{range, delta}])
  end

  @doc """
  Perform a series of shifts in a single pass.

  When shifting comments from block A to block B, naively using two passes of `shift_comments/3` would result
  in all comments ending up in either region A or region B (because A would move to B, then all B back to A)
  This function exists to make sure that a comment is only moved once during the swap.
  """
  def shift_comments(comments, shifts) do
    comments
    |> Enum.map(fn comment ->
      if delta = Enum.find_value(shifts, fn {range, delta} -> comment.line in range && delta end) do
        %{comment | line: max(comment.line + delta, 1)}
      else
        comment
      end
    end)
    |> Enum.sort_by(& &1.line)
  end

  @doc """
  Takes a list of nodes and clumps them up, setting `end_of_expression: [newlines: x]` to 1 for all but the final node,
  which gets 2 instead, (hopefully!) creating an empty line before whatever follows.
  """
  def reset_newlines([]), do: []
  def reset_newlines(nodes), do: reset_newlines(nodes, [])

  def reset_newlines([node], acc), do: Enum.reverse([set_newlines(node, 2) | acc])

  def reset_newlines([node | nodes], acc), do: reset_newlines(nodes, [set_newlines(node, 1) | acc])

  defp set_newlines({directive, meta, children}, newline) do
    updated_meta =
      Keyword.update(
        meta,
        :end_of_expression,
        [newlines: newline],
        &Keyword.put(&1, :newlines, newline)
      )

    {directive, updated_meta, children}
  end

  def max_line([_ | _] = list), do: list |> List.last() |> max_line()

  def max_line(ast) do
    meta =
      case ast do
        {_, meta, _} ->
          meta

        _ ->
          []
      end

    if max_line = meta[:closing][:line] do
      max_line
    else
      {_, max_line} =
        Macro.prewalk(ast, 0, fn
          {_, meta, _} = ast, max -> {ast, max(meta[:line] || max, max)}
          ast, max -> {ast, max}
        end)

      max_line
    end
  end

  @doc """
  Moves comments along with `nodes`, a list of siblings that has been reordered.

  `prev_last_line` is the last line before the siblings, like the line of the `[`, `%{` or `do` that
  opens their container. See `comment_regions/3` for which comments move with which node.
  """
  def order_line_meta_and_comments(nodes, comments, prev_last_line) do
    {regions, comments} =
      nodes
      |> Enum.sort_by(&meta(&1)[:line])
      |> comment_regions(comments, prev_last_line)

    place_nodes_and_comments(nodes, regions, comments, prev_last_line)
  end

  @doc """
  Splits the block's lines into one region per statement, so the statement's comments can move with it.

  Nodes must all be siblings, passed in their original order.

  A region runs from the comment lines directly above its node (no blank line between them) up to the next node's
  region. That covers comments within the node, like those in a multi-line keyword list, plus any standalone
  comment block between it and the next node. Nodes sharing a line can't be told apart, so they share a region.

  Comments outside the nodes' regions (on or before `prev_last_line`, separated from the first node by a blank
  line, or after the last node) aren't owned, and keep their lines.

  Returns the regions, in order, as `{node_lines, first_line, line_count, comments}`, plus the unowned comments.
  """
  def comment_regions(nodes, comments, prev_last_line) do
    {regions, comments, last_line} =
      nodes
      |> Enum.filter(&meta(&1)[:line])
      |> Enum.reduce({[], comments, prev_last_line}, fn node, {regions, comments, prev_last_line} ->
        line = meta(node)[:line]
        last_line = max(last_line(node), prev_last_line)
        {before, comments} = Enum.split_with(comments, &(&1.line > prev_last_line and &1.line < line))
        {inner, comments} = Enum.split_with(comments, &(&1.line > prev_last_line and &1.line in line..last_line//1))

        case regions do
          [{node_lines, first_line, owned} | regions] when line <= prev_last_line ->
            {[{node_lines.first..last_line//1, first_line, owned ++ inner} | regions], comments, last_line}

          _ ->
            {floating, leading} = split_leading_comments(before, line)

            {regions, comments} =
              case regions do
                [{node_lines, first_line, owned} | regions] ->
                  {[{node_lines, first_line, owned ++ floating} | regions], comments}

                [] ->
                  {regions, floating ++ comments}
              end

            first_line =
              case leading do
                [] -> line
                [%{line: first_line} | _] -> first_line
              end

            {[{line..last_line//1, first_line, leading ++ inner} | regions], comments, last_line}
        end
      end)

    {regions, _} =
      Enum.reduce(regions, {[], last_line + 1}, fn {node_lines, first_line, owned}, {regions, next_line} ->
        {[{node_lines, first_line, next_line - first_line, owned} | regions], first_line}
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

  @doc """
  Lays out the reordered `nodes` and the `regions` they came from (see `comment_regions/3`) back to back, starting
  just after `prev_last_line`.

  Shifting each region as a whole keeps the line gaps the formatter uses to place blank lines around comments, and
  since the regions tile the original lines, the nodes still take up the same lines. Nodes outside every region
  (new nodes, or ones moved in from elsewhere) take up no lines: they share the line of the node before them.
  Comments of regions whose nodes were all dropped are placed after the last node.
  """
  def place_nodes_and_comments(nodes, regions, comments, prev_last_line) do
    nodes = Enum.map(nodes, &{&1, find_region(regions, &1)})

    first_line =
      case regions do
        [{_, first_line, _, _} | _] -> first_line
        [] -> prev_last_line + 1
      end

    # Nodes that shared a line need a line each now. The regions have no lines to spare, but we can take them from
    # any blank lines before the first region; otherwise they keep sharing a line, and lose the blank line between them.
    shared = Enum.count(nodes, &elem(&1, 1)) - (nodes |> Enum.map(&elem(&1, 1)) |> Enum.uniq() |> Enum.count(& &1))

    floor =
      comments
      |> Enum.filter(&(&1.line > prev_last_line and &1.line < first_line))
      |> Enum.reduce(prev_last_line, &max(&1.line, &2))

    start_line = max(first_line - shared, floor + 1)

    acc = %{
      line: start_line,
      spare: max(first_line - start_line, 0),
      prev_line: prev_last_line,
      # if we took lines from before the first region, the comment now starting the block keeps the gap before it
      prev_newlines: if(start_line < first_line, do: first_line - floor),
      prev_moved?: start_line < first_line,
      deltas: %{},
      comments: comments
    }

    {nodes, acc} =
      Enum.map_reduce(nodes, acc, fn {node, region}, acc ->
        case region do
          # ending on the line of the node before it, so a multi-line node can keep its lines without overlapping any
          # comments still to be placed
          nil ->
            node =
              if meta(node)[:line],
                do: shift_line(node, acc.prev_line - last_line(node)),
                else: set_line(node, acc.prev_line, delete_newlines: false)

            {node, %{acc | prev_newlines: meta(node)[:end_of_expression][:newlines], prev_moved?: true}}

          {node_lines, _, _, _} when is_map_key(acc.deltas, node_lines) and acc.spare > 0 ->
            node = shift_line(node, acc.line - meta(node)[:line])
            newlines = meta(node)[:end_of_expression][:newlines]

            {node,
             %{
               acc
               | line: acc.line + 1,
                 spare: acc.spare - 1,
                 prev_line: last_line(node),
                 prev_newlines: newlines,
                 prev_moved?: true
             }}

          {node_lines, _, _, _} when is_map_key(acc.deltas, node_lines) ->
            node = shift_line(node, acc.deltas[node_lines])
            {node, %{acc | prev_line: max(acc.prev_line, last_line(node))}}

          {node_lines, first_line, line_count, owned} ->
            line = meta(node)[:line]
            delta = acc.line - first_line

            node =
              if delta == 0 do
                node
              else
                shift_line(node, delta)
              end

            node_last_line = last_line(node)
            owned = Enum.map(owned, &%{&1 | line: &1.line + delta})
            prev_moved? = delta != 0

            newline_count =
              if prev_moved? or acc.prev_moved? do
                acc.prev_newlines
              else
                0
              end

            {node,
             %{
               acc
               | line: acc.line + line_count,
                 prev_line: node_last_line,
                 prev_newlines:
                   if(Enum.all?(owned, &(&1.line <= node_last_line)), do: meta(node)[:end_of_expression][:newlines]),
                 prev_moved?: prev_moved?,
                 deltas: Map.put(acc.deltas, node_lines, delta),
                 comments: fix_leading_newlines(owned, line + delta, newline_count) ++ acc.comments
             }}
        end
      end)

    acc =
      regions
      |> Enum.reject(fn {node_lines, _, _, _} -> is_map_key(acc.deltas, node_lines) end)
      |> Enum.reduce(acc, fn {_, first_line, line_count, owned}, acc ->
        owned = Enum.map(owned, &%{&1 | line: &1.line + acc.line - first_line})
        %{acc | line: acc.line + line_count, comments: owned ++ acc.comments}
      end)

    {nodes, Enum.sort_by(acc.comments, & &1.line)}
  end

  defp find_region(regions, node) do
    line = meta(node)[:line]
    line && Enum.find(regions, fn {node_lines, _, _, _} -> line in node_lines end)
  end

  # When a region's leading comment directly follows the node placed before it, the formatter ignores the node's
  # newlines (as set when regrouping the nodes) in favor of the comment's `previous_eol_count`, which is from wherever
  # the comment used to be. Where either one moved, bumping the count keeps the blank line the node asks for.
  defp fix_leading_newlines([%{line: comment_line} = comment | owned], line, newlines)
       when comment_line < line and is_integer(newlines) and newlines > 0 do
    [%{comment | previous_eol_count: max(comment.previous_eol_count, newlines)} | owned]
  end

  defp fix_leading_newlines(owned, _, _), do: owned

  @doc """
  The last line of a node, including the lines of any closing delimiters (`)`, `]`, `end`, etc) within it
  """
  def last_line({_, meta, _} = ast) when is_list(meta), do: meta[:end_of_expression][:line] || do_last_line(ast)
  def last_line(ast), do: do_last_line(ast)

  defp do_last_line(ast) do
    {_, last_line} =
      Macro.prewalk(ast, 0, fn
        {_, meta, _} = ast, max when is_list(meta) ->
          lines = [meta[:line], meta[:closing][:line], meta[:end][:line], meta[:end_of_expression][:line]]
          {ast, lines |> Enum.filter(&is_integer/1) |> Enum.max(fn -> max end) |> max(max)}

        ast, max ->
          {ast, max}
      end)

    last_line
  end

  # typical node
  def meta({_, meta, _}), do: meta
  # kwl tuple ala a: :b
  def meta({{_, meta, _}, _}), do: meta
  def meta(_), do: nil

  @doc """
  Returns all comments "for" a node, including on the line before it.
  see `comments_for_lines` for more
  """
  def comments_for_node({_, m, _} = node, comments) do
    last_line = m[:end_of_expression][:line] || max_line(node)
    comments_for_lines(comments, m[:line], last_line)
  end

  @doc """
  Gets all comments in range start_line..last_line, and any comments immediately before start_line.s

    1. code
    2. # a
    3. # b
    4. code # c
    5. # d
    6. code
    7. # e

  here, comments_for_lines(comments, 4, 6) is "a", "b", "c", "d"
  """
  def comments_for_lines(comments, start_line, last_line) do
    comments |> Enum.reverse() |> comments_for_lines(start_line, last_line, [], [])
  end

  defp comments_for_lines(reversed_comments, start, last, match, acc)

  defp comments_for_lines([], _, _, match, acc), do: {Enum.reverse(match), acc}

  defp comments_for_lines([%{line: line} = comment | rev_comments], start, last, match, acc) do
    cond do
      # after our block - no match
      line > last -> comments_for_lines(rev_comments, start, last, match, [comment | acc])
      # after start, before last -- it's a match!
      line >= start -> comments_for_lines(rev_comments, start, last, [comment | match], acc)
      # this is a comment immediately before start, which means it's modifying this block...
      # we count that as a match, and look above it to see if it's a multiline comment
      line == start - 1 -> comments_for_lines(rev_comments, start - 1, last, [comment | match], acc)
      # comment before start - we've thus iterated through all comments which could be in our range
      true -> {match, Enum.reverse(rev_comments, [comment | acc])}
    end
  end
end
