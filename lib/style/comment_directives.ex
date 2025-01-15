# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.CommentDirectives do
  @moduledoc """
  Leave a comment for Styler asking it to maintain code in a certain way.

  `# styler:sort` maintains sorting of wordlists (by string comparison) and lists (string comparison of code representation)
  """

  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  def run(zipper, ctx) do
    {zipper, comments} =
      ctx.comments
      |> Enum.filter(&(&1.text == "# styler:sort"))
      |> Enum.map(& &1.line)
      |> Enum.reduce({zipper, ctx.comments}, fn line, {zipper, comments} ->
        found =
          Zipper.find(zipper, fn node ->
            node_line = Style.meta(node)[:line] || -1
            node_line >= line
          end)

        if found do
          {node, _} = found
          {sorted, comments} = sort(node, ctx.comments)
          {Zipper.replace(found, sorted), comments}
        else
          {zipper, comments}
        end
      end)

    {zipper, comments} =
      comments
      |> Enum.filter(&(&1.text == "# styler:sort-phx-router"))
      |> Enum.map(& &1.line)
      |> Enum.reduce({zipper, comments}, fn line, {zipper, comments} ->
        found =
          Zipper.find(zipper, fn node ->
            node_line = Style.meta(node)[:line] || -1
            node_line >= line
          end)

        if found do
          sort_phx(found, comments)
        else
          {zipper, comments}
        end
      end)

    {:halt, zipper, %{ctx | comments: comments}}
  end

  defp sort_phx({node, meta}, comments) do
    IO.puts("sorting")
    # @TODO one pass reduce for this
    {phx, not_phx} =
      Enum.split_with([node | meta.r], fn
        {x, _, _} -> x in ~w(pipeline pipe_through scope get put patch post delete resources)a
        _ -> false
      end)

    {pipelines, routes} = Enum.split_with(phx, &match?({x, _, _} when x in [:pipeline, :pipe_through], &1))

    pipelines = recursive_sort(pipelines)
    routes = recursive_sort(routes)

    {[node | siblings], comments} =
      Style.order_line_meta_and_comments(pipelines ++ routes ++ not_phx, comments, Style.meta(node)[:line])

    {{node, %{meta | r: siblings}}, comments}
  end

  defp recursive_sort(list) when is_list(list) do
    list
    |> Enum.map(fn {f, m, children} ->
      children =
        Enum.map(children, fn
          [{{:__block__, m1, [:do]}, {:__block__, m2, list}}] ->
            [{{:__block__, m1, [:do]}, {:__block__, m2, recursive_sort(list)}}]

          other ->
            other
        end)

      {f, m, children}
    end)
    |> Enum.sort_by(fn
      {f, _, [{:__block__, _, [literal]} | _]} ->
        #@TODO get/post/put/patch/delete/resources precedence
        {literal, f}

      other ->
        other
    end)
  end

  # defstruct with a syntax-sugared keyword list hits here
  defp sort({parent, meta, [list]} = node, comments) when parent in ~w(defstruct __block__)a and is_list(list) do
    list = Enum.sort_by(list, &Macro.to_string/1)
    line = meta[:line]
    # no need to fix line numbers if it's a single line structure
    {list, comments} =
      if line == Style.max_line(node),
        do: {list, comments},
        else: Style.order_line_meta_and_comments(list, comments, line)

    {{parent, meta, [list]}, comments}
  end

  # defstruct with a literal list
  defp sort({:defstruct, meta, [{:__block__, _, [_]} = list]}, comments) do
    {list, comments} = sort(list, comments)
    {{:defstruct, meta, [list]}, comments}
  end

  defp sort({:%{}, meta, list}, comments) when is_list(list) do
    {{:__block__, meta, [list]}, comments} = sort({:__block__, meta, [list]}, comments)
    {{:%{}, meta, list}, comments}
  end

  defp sort({:%, m, [struct, map]}, comments) do
    {map, comments} = sort(map, comments)
    {{:%, m, [struct, map]}, comments}
  end

  defp sort({:sigil_w, sm, [{:<<>>, bm, [string]}, modifiers]}, comments) do
    # ew. gotta be a better way.
    # this keeps indentation for the sigil via joiner, while prepend and append are the bookending whitespace
    {prepend, joiner, append} =
      case Regex.run(~r|^\s+|, string) do
        # oneliner like `~w|c a b|`
        nil -> {"", " ", ""}
        # multiline like
        # `"\n  a\n  list\n  long\n  of\n  static\n  values\n"`
        #   ^^^^ `prepend`       ^^^^ `joiner`             ^^ `append`
        # note that joiner and prepend are the same in a multiline (unsure if this is always true)
        # @TODO: get all 3 in one pass of a regex. probably have to turn off greedy or something...
        [joiner] -> {joiner, joiner, ~r|\s+$| |> Regex.run(string) |> hd()}
      end

    string = string |> String.split() |> Enum.sort() |> Enum.join(joiner)
    {{:sigil_w, sm, [{:<<>>, bm, [prepend, string, append]}, modifiers]}, comments}
  end

  defp sort({:=, m, [lhs, rhs]}, comments) do
    {rhs, comments} = sort(rhs, comments)
    {{:=, m, [lhs, rhs]}, comments}
  end

  defp sort({:@, m, [{a, am, [assignment]}]}, comments) do
    {assignment, comments} = sort(assignment, comments)
    {{:@, m, [{a, am, [assignment]}]}, comments}
  end

  defp sort({key, value}, comments) do
    {value, comments} = sort(value, comments)
    {{key, value}, comments}
  end

  defp sort(x, comments), do: {x, comments}
end
