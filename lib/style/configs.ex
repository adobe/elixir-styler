# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Configs do
  def run({{:import, _, [{:__aliases__, _, [:Config]}]}, _} = zipper, %{config?: true} = ctx) do
    {:skip, zipper, Map.put(ctx, :mix_config?, true)}
  end

  def run({{:config, _, args} = config, zm}, %{mix_config?: true} = ctx) when is_list(args) do
    {configs, others} = Enum.split_while(zm.r, &match?({:config, _, [_|_]}, &1))
    [config | configs] = Enum.sort_by([config | configs], &Styler.Style.update_all_meta(&1, fn _ -> nil end), :desc)
    zm = %{zm | l: configs ++ zm.l, r: others}
    {:skip, {config, zm}, ctx}
  end

  def run(zipper, %{config?: true} = ctx) do
    {:cont, zipper, ctx}
  end

  def run(zipper, %{file: file} = ctx) do
    if file =~ ~r|config/.*\.exs| do
      {:cont, zipper, Map.put(ctx, :config?, true)}
    else
      {:halt, zipper, ctx}
    end
  end
end
