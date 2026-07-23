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

    {nodes, comments, rest} =
      if changed?(nodes) do
        # config line is the first line to be used as part of this block
        {node_comments, _} = Style.comments_for_node(config, comments)
        first_line = min(List.first(node_comments)[:line] || cfm[:line], cfm[:line])

        # Sorting and re-spacing can make the block taller (config groups gain blank lines between them).
        # reodering means the block can grow past `rest` and its comments, causing the comments for `rest` to get sucked up into our block.

        # `configs`/`assignments` are reverse-ordered (`accumulate` prepends), so we can't just take the last node.
        max_before_ordering = [config | configs ++ assignments] |> Enum.map(&Style.max_line/1) |> Enum.max()
        {block_comments, tail_comments} = Enum.split_while(comments, &(&1.line <= max_before_ordering))

        {nodes, block_comments} = Style.order_line_meta_and_comments(nodes, block_comments, first_line)

        delta = Style.max_line(nodes) - max_before_ordering
        tail_comments = Enum.map(tail_comments, &%{&1 | line: &1.line + delta})
        rest = Style.shift_line(rest, delta)

        {nodes, Enum.sort_by(block_comments ++ tail_comments, & &1.line), rest}
      else
        {nodes, comments, rest}
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

  defp accumulate([{:config, _, [_, _ | _]} = c | siblings], cs, as), do: accumulate(siblings, [c | cs], as)
  defp accumulate([{:=, _, [_lhs, _rhs]} = a | siblings], cs, as), do: accumulate(siblings, cs, [a | as])
  defp accumulate(rest, configs, assignments), do: {configs, assignments, rest}
end
