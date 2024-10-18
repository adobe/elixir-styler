# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Configs do
  @moduledoc """
  Orders `Config.config/2,3` stanzas in configuration files.

  - ordering is done only within immediate-sibling config statements
  - assignments are moved above the configuration blocks
  - any non `config/2,3` or assignment (`=/2`) calls mark the end of a sorting block.
    this is support having conditional blocks (`if/case/cond`) and `import_config` stanzas between blocks

  ### Breakages

  If you configure the same values multiple times, Styler may swap their orders

  **Before**

    line 04: config :foo, bar: :zab
    line 40: config :foo, bar: :baz

    # Application.fetch_env!(:foo)[:bar] => :baz

  **After**

    line 04: config :foo, bar: :baz
    line 05: config :foo, bar: :zab

    # Application.fetch_env!(:foo)[:bar] => :zab

  **Fix**

  The reason Styler sorts configuration is to help you noticed these duplicated configuration stanzas.
  Delete the duplicative/erroneous stanza and life will be good.
  """

  alias Styler.Style

  def run({{:import, _, [{:__aliases__, _, [:Config]}]}, _} = zipper, %{config?: true} = ctx) do
    {:skip, zipper, Map.put(ctx, :mix_config?, true)}
  end

  def run({{:config, cfm, [_, _ | _]} = config, zm}, %{mix_config?: true, comments: comments} = ctx) do
    # all of these list are reversed due to the reduce
    {configs, assignments, rest} = accumulate(zm.r, [], [])
    # @TODO
    # okay so comments between nodes that we moved.......
    # lets just push them out of the way (???). so
    # 1. figure out first/last possible lines we're talking about here
    # 2. only pass comments in that range off
    # 3. split those comments into "moved, didn't move"
    # 4. for any "didn't move" comments... move them to the top?
    #
    # also, should i just do a scan of the configs ++ assignments, and see if any of them have lines out of order,
    # and decide from there whether or not i want to do set_lines

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

    # `set_lines` performs better than `fix_line_numbers` for a large number of nodes moving, as it moves their comments with them
    # however, it will also move any comments not associated with a node, causing wildly unpredictable sad times!
    # so i'm trying to guess which change will be less damaging.
    # moving >=3 nodes hints that this is an initial run, where `set_lines` definitely outperforms.
    {nodes, comments} =
      if changed?(nodes) do
        # after running, this block should take up the same # of lines that it did before
        # the first node of `rest` is greater than the highest line in configs, assignments
        # config line is the first line to be used as part of this block
        # that will change when we consider preceding comments
        {node_comments, _} = comments_for_node(config, comments)
        first_line = min(List.last(node_comments)[:line] || cfm[:line], cfm[:line])
        set_lines(nodes, comments, first_line)
      else
        {nodes, comments}
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

  defp set_lines(nodes, comments, first_line) do
    {nodes, comments, node_comments} = set_lines(nodes, comments, first_line, [], [])
    # @TODO if there are dangling comments between the nodes min/max, push them somewhere?
    # likewise deal with conflicting line comments?
    {nodes, Enum.sort_by(comments ++ node_comments, & &1.line)}
  end

  def set_lines([], comments, _, node_acc, c_acc), do: {Enum.reverse(node_acc), comments, c_acc}

  def set_lines([{_, meta, _} = node | nodes], comments, start_line, n_acc, c_acc) do
    line = meta[:line]
    last_line = meta[:end_of_expression][:line] || Style.max_line(node)

    {node, node_comments, comments} =
      if start_line == line do
        {node, [], comments}
      else
        {mine, comments} = comments_for_lines(comments, line, last_line)
        line_with_comments = (List.first(mine)[:line] || line) - (List.first(mine)[:previous_eol_count] || 1) + 1

        if line_with_comments == start_line do
          {node, mine, comments}
        else
          shift = start_line - line_with_comments
          node = Style.shift_line(node, shift)

          mine = Enum.map(mine, &%{&1 | line: &1.line + shift})
          {node, mine, comments}
        end
      end

    {_, meta, _} = node
    # @TODO what about comments that were free floating between blocks? i'm just ignoring them and maybe always will...
    # kind of just want to shove them to the end though, so that they don't interrupt existing stanzas.
    # i think that's accomplishable by doing a final call above that finds all comments in the comments list that weren't moved
    # and which are in the range of start..finish and sets their lines to finish!
    last_line = meta[:end_of_expression][:line] || Style.max_line(node)
    last_line = (meta[:end_of_expression][:newlines] || 1) + last_line
    set_lines(nodes, comments, last_line, [node | n_acc], node_comments ++ c_acc)
  end

  defp comments_for_node({_, m, _} = node, comments) do
    last_line = m[:end_of_expression][:line] || Style.max_line(node)
    comments_for_lines(comments, m[:line], last_line)
  end

  defp comments_for_lines(comments, start_line, last_line) do
    comments
    |> Enum.reverse()
    |> comments_for_lines(start_line, last_line, [], [])
  end

  defp comments_for_lines(reversed_comments, start, last, match, acc)

  defp comments_for_lines([], _, _, match, acc), do: {Enum.reverse(match), acc}

  defp comments_for_lines([%{line: line} = comment | rev_comments], start, last, match, acc) do
    cond do
      line > last -> comments_for_lines(rev_comments, start, last, match, [comment | acc])
      line >= start -> comments_for_lines(rev_comments, start, last, [comment | match], acc)
      # @TODO bug: match line looks like `x = :foo # comment for x`
      # could account for that by pre-running the formatter on config files :/
      line == start - 1 -> comments_for_lines(rev_comments, start - 1, last, [comment | match], acc)
      true -> {match, Enum.reverse(rev_comments, [comment | acc])}
    end
  end

  defp accumulate([{:config, _, [_, _ | _]} = c | siblings], cs, as), do: accumulate(siblings, [c | cs], as)
  defp accumulate([{:=, _, [_lhs, _rhs]} = a | siblings], cs, as), do: accumulate(siblings, cs, [a | as])
  defp accumulate(rest, configs, assignments), do: {configs, assignments, rest}
end
