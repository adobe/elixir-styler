# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Mix.Tasks.Speedo do
  @shortdoc "Oh snap"
  @moduledoc """
  Credo with more vroom and no features

    mix speedo
  """

  use Mix.Task

  @impl Mix.Task
  def run(_) do
    {_, formatter_opts} = Mix.Tasks.Format.formatter_for_file("lib/mix.exs")
    formatter_opts = Keyword.drop(formatter_opts, [:sigils, :plugins])

    files =
      case Keyword.fetch(formatter_opts, :inputs) do
        :error -> Mix.raise("mix speedo relies on `.formatter.exs` for its input glob")
        {:ok, inputs} -> inputs
      end

    files
    |> Stream.flat_map(fn path ->
      path
      |> Path.expand()
      |> Path.wildcard(match_dot: true)
      |> Enum.filter(&String.ends_with?(&1, [".ex", "exs"]))
    end)
    |> Task.async_stream(
      fn file -> file |> File.read!() |> Styler.lint(file) end,
      ordered: false,
      timeout: :infinity
    )
    |> Enum.reduce([], fn {:ok, errors}, all_errors -> List.flatten(errors, all_errors) end)
    |> check!()
  end

  defp check!([]) do
    :ok
  end

  defp check!(errors) do
    errors
    |> Enum.reject(&is_nil/1)
    |> Enum.group_by(& &1.check)
    |> Enum.sort_by(fn {check, _} -> check end)
    |> Enum.each(fn {check, errors} ->
      check = check |> to_string() |> String.trim_leading("Elixir.")
      Mix.shell().error("\n#{check} violations")
      Mix.shell().error("--------------------------------------------------------------")

      errors = Enum.sort_by(errors, &{&1.file, &1.line})

      for %{file: file, line: line, message: message} <- errors do
        Mix.shell().info([IO.ANSI.light_yellow(), inspect(message), IO.ANSI.reset()])
        Mix.shell().info("  #{Path.relative_to_cwd(file)}:#{line}")
      end
    end)

    System.stop(1)
  end
end
