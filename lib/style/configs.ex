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

  def run({{:config, _, [_, _ | _]} = config, zm}, %{mix_config?: true} = ctx) do
    # all of these list are reversed due to the reduce
    {configs, assignments, rest} = accumulate(zm.r, [], [])

    left_siblings = assignments |> Enum.reverse() |> Style.reset_newlines() |> Enum.reverse(zm.l)

    [config | left_siblings] =
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
      |> Style.fix_line_numbers(List.first(rest))
      |> Enum.reverse(left_siblings)

    {:skip, {config, %{zm | l: left_siblings, r: rest}}, ctx}
  end

  def run(zipper, %{config?: true} = ctx) do
    {:cont, zipper, ctx}
  end

  def run(zipper, %{file: file} = ctx) do
    if file =~ ~r|config/.*\.exs| or file =~ ~r|rel/overlays/.*\.exs| do
      {:cont, zipper, Map.put(ctx, :config?, true)}
    else
      {:halt, zipper, ctx}
    end
  end

  defp accumulate([{:config, _, [_, _ | _]} = c | siblings], cs, as), do: accumulate(siblings, [c | cs], as)
  defp accumulate([{:=, _, [_lhs, _rhs]} = a | siblings], cs, as), do: accumulate(siblings, cs, [a | as])
  defp accumulate(rest, configs, assignments), do: {configs, assignments, rest}
end
