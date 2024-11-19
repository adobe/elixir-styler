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

  # Deprecated in 1.18
  # rewrite patterns of `first..last = ...` to `first..last//_ = ...`
  defp style({:=, m, [{:.., _, [_first, _last]} = range, rhs]}), do: {:=, m, [rewrite_range_match(range), rhs]}
  defp style({:->, m, [[{:.., _, [_first, _last]} = range], rhs]}), do: {:->, m, [[rewrite_range_match(range)], rhs]}
  defp style({:<-, m, [{:.., _, [_first, _last]} = range, rhs]}), do: {:<-, m, [rewrite_range_match(range), rhs]}

  defp style({def, dm, [{x, xm, params} | rest]}) when def in ~w(def defp)a and is_list(params),
    do: {def, dm, [{x, xm, Enum.map(params, &rewrite_range_match/1)} | rest]}

  # Deprecated in 1.18
  # List.zip => Enum.zip
  defp style({{:., dm_, [{:__aliases__, am, [:List]}, :zip]}, fm, arg}),
    do: {{:., dm_, [{:__aliases__, am, [:Enum]}, :zip]}, fm, arg}

  # Logger.warn => Logger.warning
  # Started to emit warning after Elixir 1.15.0
  defp style({{:., dm, [{:__aliases__, am, [:Logger]}, :warn]}, funm, args}),
    do: {{:., dm, [{:__aliases__, am, [:Logger]}, :warning]}, funm, args}

  # Path.safe_relative_to/2 => Path.safe_relative/2
  # TODO: Remove after Elixir v1.19
  defp style({{:., dm, [{_, _, [:Path]} = mod, :safe_relative_to]}, funm, args}),
    do: {{:., dm, [mod, :safe_relative]}, funm, args}

  # Pipe version for:
  # Path.safe_relative_to/2 => Path.safe_relative/2
  defp style({:|>, m, [lhs, {{:., dm, [{:__aliases__, am, [:Path]}, :safe_relative_to]}, funm, args}]}),
    do: {:|>, m, [lhs, {{:., dm, [{:__aliases__, am, [:Path]}, :safe_relative]}, funm, args}]}

  if Version.match?(System.version(), ">= 1.16.0-dev") do
    # File.stream!(file, options, line_or_bytes) => File.stream!(file, line_or_bytes, options)
    defp style({{:., _, [{_, _, [:File]}, :stream!]} = f, fm, [path, {:__block__, _, [modes]} = opts, lob]})
         when is_list(modes),
         do: {f, fm, [path, lob, opts]}

    # Pipe version for File.stream!
    defp style({:|>, m, [lhs, {{_, _, [{_, _, [:File]}, :stream!]} = f, fm, [{:__block__, _, [modes]} = opts, lob]}]})
         when is_list(modes),
         do: {:|>, m, [lhs, {f, fm, [lob, opts]}]}
  end

  # For ranges where `start > stop`, you need to explicitly include the step
  # Enum.slice(enumerable, 1..-2) => Enum.slice(enumerable, 1..-2//1)
  # String.slice("elixir", 2..-1) => String.slice("elixir", 2..-1//1)
  defp style({{:., _, [{_, _, [module]}, :slice]} = f, funm, [enumerable, {:.., _, [_, _]} = range]})
       when module in [:Enum, :String],
       do: {f, funm, [enumerable, add_step_to_decreasing_range(range)]}

  # Pipe version for {Enum,String}.slice
  defp style({:|>, m, [lhs, {{:., _, [{_, _, [mod]}, :slice]} = f, funm, [{:.., _, [_, _]} = range]}]})
       when mod in [:Enum, :String],
       do: {:|>, m, [lhs, {f, funm, [add_step_to_decreasing_range(range)]}]}

  # ~R is deprecated in favor of ~r
  defp style({:sigil_R, m, args}), do: {:sigil_r, m, args}

  # For a decreasing range, we must use Date.range/3 instead of Date.range/2
  defp style({{:., _, [{:__aliases__, _, [:Date]}, :range]} = funm, dm, [first, last]} = block) do
    if add_step_to_date_range?(first, last),
      do: {funm, dm, [first, last, -1]},
      else: block
  end

  # Pipe version for Date.range/2
  defp style({:|>, pm, [first, {{:., _, [{:__aliases__, _, [:Date]}, :range]} = funm, dm, [last]}]} = pipe) do
    if add_step_to_date_range?(first, last),
      do: {:|>, pm, [first, {funm, dm, [last, -1]}]},
      else: pipe
  end

  # use :eof instead of :all in IO.read/2 and IO.binread/2
  defp style({{:., _, [{:__aliases__, _, [:IO]}, fun]} = fm, dm, [{:__block__, am, [:all]}]})
       when fun in [:read, :binread],
       do: {fm, dm, [{:__block__, am, [:eof]}]}

  defp style({{:., _, [{:__aliases__, _, [:IO]}, fun]} = fm, dm, [device, {:__block__, am, [:all]}]})
       when fun in [:read, :binread],
       do: {fm, dm, [device, {:__block__, am, [:eof]}]}

  defp style(node), do: node

  defp rewrite_range_match({:.., dm, [first, {_, m, _} = last]}), do: {:"..//", dm, [first, last, {:_, m, nil}]}
  defp rewrite_range_match(x), do: x

  defp add_step_to_date_range?(first, last) do
    with {:ok, f} <- extract_date_value(first),
         {:ok, l} <- extract_date_value(last),
         # for ex1.14 compat, use compare instead of after?
         :gt <- Date.compare(f, l) do
      true
    else
      _ -> false
    end
  end

  defp add_step_to_decreasing_range({:.., rm, [first, {_, lm, _} = last]} = range) do
    with {:ok, start} <- extract_value_from_range(first),
         {:ok, stop} <- extract_value_from_range(last),
         true <- start > stop do
      step = {:__block__, [token: "1", line: lm[:line]], [1]}
      {:"..//", rm, [first, last, step]}
    else
      _ -> range
    end
  end

  # Extracts the positive or negative integer from the given range block
  defp extract_value_from_range({:__block__, _, [value]}) when is_integer(value), do: {:ok, value}
  defp extract_value_from_range({:-, _, [{:__block__, _, [value]}]}) when is_integer(value), do: {:ok, -value}
  defp extract_value_from_range(_), do: :non_int

  defp extract_date_value({:sigil_D, _, [{:<<>>, _, [date]}, []]}), do: Date.from_iso8601(date)
  defp extract_date_value(_), do: :unknown
end
