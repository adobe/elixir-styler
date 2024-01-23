defmodule Styler.Linter.Comments do
  @moduledoc false
  # https://hexdocs.pm/credo/config_comments.html

  def parse(comments) do
    Enum.flat_map(comments, fn %{text: text, line: line} ->
      with "# credo:disable-for-" <> rest <- text,
           {line, rest} <- parse_line(rest, line),
           {:ok, check} <- parse_check(rest) do
        [{check, line}]
      else
        _ -> []
      end
    end)
  end

  defp parse_line("this-file" <> rest, line) do
    unless line == 1, do: IO.puts("warning: `# credo:disable-for-this-file` should be first line of file")
    {:*, rest}
  end

  defp parse_line("next-line" <> rest, line) do
    {line + 1, rest}
  end

  defp parse_line("lines:" <> rest, line) do
    case Integer.parse(rest) do
      {int, rest} when int > 0 ->
        {(line + 1)..(line + int), rest}

      {_, _} ->
        IO.puts("warning: credo:disable-for-lines with negative number ignored")
        :error

      :error ->
        IO.puts("warning: invalid config `disable-for-#{rest}` at line #{line}")
        :error
    end
  end

  defp parse_line(rest, line) do
    IO.puts("warning: invalid config `disable-for-#{rest}` at line #{line}")
    :error
  end

  defp parse_check(string) do
    case String.trim(string) do
      "" ->
        {:ok, :*}

      "Credo.Check." <> rest ->
        case Regex.run(~r|(\w+\.\w+)$|, rest) do
          [_, check] -> {:ok, String.to_atom("Elixir.Credo.Check.#{check}")}
          _ -> :error
        end

      _ ->
        :error
    end
  end
end
