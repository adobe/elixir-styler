# Copyright 2025 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.InlineAttrs do
  @moduledoc false
  alias Styler.Style
  alias Styler.Zipper

  def run(zipper, ctx) do
    if defstructz = Zipper.find(zipper, &match?({:defmodule, _, _}, &1)) do
      body_zipper = defstructz |> Zipper.down() |> Zipper.right() |> Zipper.down() |> Zipper.down() |> Zipper.right()

      {literal_attrs, others} =
        body_zipper
        |> Zipper.children()
        |> Enum.split_with(fn
          {:@, _, [{_name, _, [{:to_timeout, _, values}]}]} -> quoted_literal?(values)
          {:@, _, [{name, _, values}]} -> name not in ~w(doc impl moduledoc)a and quoted_literal?(values)
          _ -> false
        end)

      {_, hits} =
        Macro.prewalk(others, %{}, fn
          {:@, _, [{name, _, _}]} = ast, acc ->
            def = Enum.find(literal_attrs, &match?({:@, _, [{^name, _, _}]}, &1))
            val = def && {def, ast}
            {ast, Map.update(acc, name, val, fn _ -> false end)}

          ast, acc ->
            {ast, acc}
        end)

      zipper =
        hits
        |> Enum.filter(fn {_, v} -> v end)
        |> Enum.reduce(body_zipper, fn {_, {def, ast}}, zipper ->
          {_, _, [{_, _, [value]}]} = def
          replacement = Style.set_line(value, Style.meta(ast)[:line])

          zipper
          |> Zipper.find(&match?(^def, &1))
          |> Zipper.remove()
          |> Zipper.find(&match?(^ast, &1))
          |> Zipper.replace(replacement)
          |> Zipper.top()
        end)

      {:halt, zipper, ctx}
    else
      {:halt, zipper, ctx}
    end
  end
  # Can't rely on `Macro.quoted_literal?` up front because we wrapped our literals :/
  # This function is not complete, but it's good enough for the needs here.
  defp quoted_literal?(value) when is_list(value) or is_map(value) do
    Enum.all?(value, fn
      {k, v} -> quoted_literal?(k) and quoted_literal?(v)
      value -> quoted_literal?(value)
    end)
  end

  defp quoted_literal?({:__block__, _, [value]}), do: quoted_literal?(value)
  defp quoted_literal?(value), do: Macro.quoted_literal?(value)
end
