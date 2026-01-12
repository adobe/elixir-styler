# Copyright 2025 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Mix.Tasks.Styler.RemoveUnused do
  @shortdoc "EXPERIMENTAL: uses unused import/alias/require compiler warnings to remove those lines"
  @moduledoc """
  WARNING: EXPERIMENTAL | Removes unused import/alias/require statements by compiling the app and parsing warnings, then deleting the specified lines.

  Usage:

      mix styler.remove_unused
  """
  use Mix.Task

  alias Mix.Shell.IO

  @impl Mix.Task
  def run(_) do
    # Warnings come over stderr, so gotta redirect
    {output, _} = System.cmd("mix", ~w(compile --all-warnings), stderr_to_stdout: true)

    if output =~ "warning: unused" do
      IO.info("Removing unused import/alias/require lines...\n")

      output
      |> String.split("\n\n")
      |> Stream.map(&Regex.run(~r/warning\: unused (alias|require|import).* (.*\.exs?):(\d+)\:/s, &1))
      |> Stream.filter(& &1)
      |> Stream.map(fn [_full_message, _require_or_alias, file, line] ->
        file =
          if File.exists?(file) do
            file
          else
            [umbrella_corrected] = Path.wildcard("apps/*/#{file}")
            umbrella_corrected
          end

        {file, String.to_integer(line)}
      end)
      |> Enum.group_by(fn {file, _} -> file end, fn {_, line} -> line end)
      |> Enum.sort_by(fn {file, _} -> file end)
      |> Enum.each(fn {file, lines} ->
        contents = file |> File.read!() |> String.split("\n")

        IO.info("==> #{file}")

        lines
        |> Enum.sort()
        |> Enum.each(&IO.info("#{&1}: #{Enum.at(contents, &1 - 1)}"))

        contents =
          lines
          |> Enum.sort(:desc)
          |> Enum.reduce(contents, &List.delete_at(&2, &1 - 1))
          |> Enum.join("\n")

        File.write!(file, contents)
        IO.info("")
      end)

      IO.info("Running `mix format` to remove any excess newlines.")

      Mix.Task.run("format")

      IO.info("Done.")
    else
      IO.info("No \"unused\" warnings detected, no work to do.")
    end
  end
end
