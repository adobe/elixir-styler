defmodule Styler.Style.Unless do
  @moduledoc """
  Module that rewrites unless' to use if statements as much as possible
  """

  @behaviour Styler.Style

  alias Styler.Zipper

  @operator_lookup_list [
    {:==, :!=},
    {:===, :!==},
    {:>, :<=},
    {:>=, :<}
  ]

  @operator_lookup @operator_lookup_list ++ Enum.map(@operator_lookup_list, fn {left, right} -> {right, left} end)

  @operators Enum.map(@operator_lookup, &elem(&1, 0))

  @impl true
  def run(zipper, ctx), do: {:cont, Zipper.update(zipper, &style/1), ctx}

  defp style(
         {:unless, meta,
          [
            statement,
            [{{:__block__, meta_true, [:do]}, true_condition}, {{:__block__, meta_false, [:else]}, false_condition}]
          ]}
       ) do
    {:if, meta,
     [statement, [{{:__block__, meta_true, [:do]}, false_condition}, {{:__block__, meta_false, [:else]}, true_condition}]]}
  end

  defp style({:unless, meta, [{operator, condition_meta, condition}, [path]]}) when operator in @operators do
    {:if, meta, [{invert_operator(operator), condition_meta, condition}, [path]]}
  end

  defp style(node), do: node

  Enum.map(@operator_lookup, fn {operator_in, operator_out} ->
    defp invert_operator(unquote(operator_in)), do: unquote(operator_out)
  end)
end
