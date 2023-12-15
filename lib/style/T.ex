defmodule T do
  @moduledoc false
  def cartesian([], _f), do: []
  def cartesian(lists, f), do: lists |> Enum.reverse() |> cartesian([], f) |> Enum.to_list()

  defp cartesian([], elems, f), do: [apply(f, elems)]

  defp cartesian([h | tail], elems, f) do
    Stream.flat_map(h, fn x -> cartesian(tail, [x | elems], f) end)
  end

  def thing(x, y) do
    {x, y}
  end
end
