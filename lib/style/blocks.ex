defmodule Styler.Style.Blocks do
  @moduledoc """
  Styles Blocks.
  Rewrites for the following Credo rules:

    * Credo.Check.Refactor.UnlessWithElse
  """

  @behaviour Styler.Style

  alias Styler.Style
  alias Styler.Zipper

  def run(zipper, ctx), do: {:cont, style(zipper), ctx}

  defp style({{:unless, _, [_condition, children]}, _} = zipper) when length(children) == 2 do
    [{{:__block__, do_meta, [:do]}, _do_body}, {{:__block__, else_meta, [:else]}, _else_body}] = children
    diff = else_meta[:line] - do_meta[:line]

    zipper =
      Zipper.update(
        zipper,
        fn {:unless, meta, children} -> {:if, meta, children} end
      )

    do_body =
      zipper
      |> Zipper.down()
      |> Zipper.right()
      |> Zipper.down()

    else_body = Zipper.right(do_body)

    new_do_body =
      else_body
      |> Zipper.node()
      |> update_line_number(&(&1 - diff))
      |> Zipper.update(fn {:__block__, meta, [:else]} -> {:__block__, meta, [:do]} end)

    new_else_body =
      do_body
      |> Zipper.node()
      |> update_line_number(&(&1 + diff))
      |> Zipper.update(fn {:__block__, meta, [:do]} -> {:__block__, meta, [:else]} end)

    zipper =
      do_body
      |> Zipper.replace(new_do_body)
      |> Zipper.right()
      |> Zipper.replace(new_else_body)

    zipper
  end

  defp style(zipper), do: zipper

  defp update_line_number(ast_node, fun) do
    Style.update_all_meta(ast_node, fn meta ->
      meta =
        if Keyword.has_key?(meta, :line) do
          Keyword.update!(meta, :line, fn line -> fun.(line) end)
        else
          meta
        end

      meta =
        if Keyword.has_key?(meta, :closing) do
          Keyword.update!(meta, :closing, fn [line: line] -> [line: fun.(line)] end)
        else
          meta
        end

      meta =
        if Keyword.has_key?(meta, :last) do
          Keyword.update!(meta, :last, fn [line: line] -> [line: fun.(line)] end)
        else
          meta
        end

      meta
    end)
  end
end
