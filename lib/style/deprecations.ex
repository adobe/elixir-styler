# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.Deprecations do
  @moduledoc """
  Transformations to soft or hard deprecations introduced on newer Elixir releases
  """

  @behaviour Styler.Style

  def run({node, meta}, ctx), do: {:cont, {style(node), meta}, ctx}

  # Logger.warn => Logger.warning
  # Started to emit warning after Elixir 1.15.0
  defp style({{:., dm, [{:__aliases__, am, [:Logger]}, :warn]}, funm, args}),
    do: {{:., dm, [{:__aliases__, am, [:Logger]}, :warning]}, funm, args}

  # Path.safe_relative_to/2 => Path.safe_relative/2 
  # Path.safe_relative/2 is available since v1.14
  # TODO: Remove after Elixir v1.19
  defp style({{:., dm, [{:__aliases__, am, [:Path]}, :safe_relative_to]}, funm, args}),
    do: {{:., dm, [{:__aliases__, am, [:Path]}, :safe_relative]}, funm, args}

  if Version.match?(System.version(), ">= 1.16.0-dev") do
    # File.stream!(file, options, line_or_bytes) => File.stream!(file, line_or_bytes, options)
    defp style(
           {{:., dm, [{:__aliases__, am, [:File]}, :stream!]}, funm,
            [path, {:__block__, _, [modes]} = options, line_or_bytes]}
         )
         when is_list(modes),
         do: {{:., dm, [{:__aliases__, am, [:File]}, :stream!]}, funm, [path, line_or_bytes, options]}

    # Enum.slice(enumerable, 1..-2) => Enum.slice(enumerable, 1..-2//1)
    defp style(
           {{:., dm, [{:__aliases__, am, [:Enum]}, :slice]}, funm,
            [enumerable, {:.., rm, [{:__block__, _, _} = first, {:-, lm, _} = last]}]}
         ) do
      line = Keyword.fetch!(lm, :line)
      step = {:__block__, [token: "1", line: line], [1]}
      range_with_step = {:"..//", rm, [first, last, step]}
      {{:., dm, [{:__aliases__, am, [:Enum]}, :slice]}, funm, [enumerable, range_with_step]}
    end
  end

  defp style(node), do: node
end
