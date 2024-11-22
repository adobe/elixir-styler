# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.CommentDirectives do
  @moduledoc "TODO"

  @behaviour Styler.Style

  alias Styler.Zipper

  def run(zipper, ctx) do
    zipper =
      ctx.comments
      |> Enum.filter(&(&1.text == "# styler:sort"))
      |> Enum.map(& &1.line)
      |> Enum.reduce(zipper, fn line, zipper ->
        found =
          Zipper.find(zipper, fn
            {_, meta, _} -> meta[:line] >= line
            _ -> false
          end)

        case found do
          nil ->
            zipper

          {{:__block__, meta, [list]}, _} when is_list(list) ->
            list = Enum.sort_by(list, fn {f, _, a} -> {f, a} end)
            Zipper.replace(found, {:__block__, meta, [list]})

          {{:sigil_w, sm, [{:<<>>, bm, [string]}, modifiers]} = node, _} ->
            dbg(node)
            # ew. gotta be a better way.
            # this keeps indentation for the sigil via joiner, while prepend and append are the bookending whitespace
            {prepend, joiner, append} =
              case Regex.run(~r|^\s+|, string) do
                # oneliner like `~w|c a b|`
                nil -> {"", " ", ""}
                # multline like
                # `"\n  a\n  list\n  long\n  of\n  static\n  values\n"`
                #   ^^^^ `prepend`       ^^^^ `joiner`             ^^ `append`
                # note that joiner and append are the same in a multline (unsure if this is always true)
                [joiner] -> {joiner, joiner, if(String.contains?(joiner, "\n"), do: "\n", else: "")}
              end

            string = string |> String.split() |> Enum.sort() |> Enum.join(joiner)
            Zipper.replace(found, {:sigil_w, sm, [{:<<>>, bm, [prepend, string, append]}, modifiers]})

          x ->
            dbg(Zipper.node(x))
            found
        end
      end)

    {:skip, zipper, ctx}
  end
end
