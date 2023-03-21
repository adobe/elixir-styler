# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Mix.Tasks.Style do
  @shortdoc "Rewrites & formats your code so you don't get as mad at Credo"
  @moduledoc """
  Formats and rewrites the given files and patterns.

    mix style mix.exs "lib/**/*.{ex,exs}" "test/**/*.{ex,exs}"

  `mix style` uses the same options as `mix format` specified in `.formatter.exs` to
  format the code, and to determine which files to style if you don't pass any as arguments

  ## Task-specific options

  * `--check-formatted` - an alias for `--check-styled`, included for compatibility with `mix format`

  * `--check-styled` - checks that the file is already styled rather than styling it.
    useful for CI.
  """

  use Mix.Task

  alias Styler.Style
  alias Styler.StyleError
  alias Styler.Zipper

  @styles [
    Styler.Style.Aliases,
    Styler.Style.Pipes
  ]

  @impl Mix.Task
  def run(args) do
    for style <- @styles, do: Code.ensure_loaded!(style)

    # we take `check_formatted` so we can easily replace `mix format`
    {opts, files} = OptionParser.parse!(args, strict: [check_styled: :boolean, check_formatted: :boolean])
    check_styled? = opts[:check_styled] || opts[:check_formatted] || false

    {_, formatter_opts} = Mix.Tasks.Format.formatter_for_file("mix.exs")

    files =
      if Enum.empty?(files) do
        case Keyword.fetch(formatter_opts, :inputs) do
          :error -> Mix.raise("you must pass file arguments or run `mix style` from the project's root directory")
          {:ok, inputs} -> inputs
        end
      else
        files
      end

    files
    |> Stream.flat_map(&(&1 |> Path.expand() |> Path.wildcard(match_dot: true)))
    |> Task.async_stream(&style_file(&1, formatter_opts, check_styled?),
      ordered: false,
      timeout: :timer.seconds(30)
    )
    |> Enum.reduce({[], []}, fn
      {:ok, :ok}, acc -> acc
      {:ok, {:exit, exit}}, {exits, not_styled} -> {[exit | exits], not_styled}
      {:ok, {:not_styled, file}}, {exits, not_styled} -> {exits, [file | not_styled]}
    end)
    |> check!()
  end

  defp check!({[], []}) do
    :ok
  end

  defp check!({[{file, exception, stacktrace} | _], _not_styled}) do
    Mix.shell().error("mix style failed for file: #{Path.relative_to_cwd(file)}")
    reraise exception, stacktrace
  end

  defp check!({_exits, [_ | _] = not_styled}) do
    Mix.raise("""
    mix style failed due to --check-styled.
    The following files are not styled:
    #{Enum.join(not_styled, "\n")}
    """)
  end

  defp style_file(file, formatter_opts, check_styled?) do
    input = String.trim(File.read!(file))
    {ast, comments} = Styler.string_to_quoted_with_comments(input)
    zipper = Zipper.zip(ast)

    output =
      @styles
      |> Enum.reduce(zipper, fn style, zipper ->
        traverser = Style.wrap_run(style)

        try do
          Zipper.traverse_while(zipper, traverser)
        rescue
          exception ->
            reraise StyleError, [exception: exception, style: style, file: file], __STACKTRACE__
        end
      end)
      |> Zipper.root()
      |> Styler.quoted_to_string(comments, formatter_opts)

    changed? = input != output

    cond do
      check_styled? and changed? -> {:not_styled, file}
      changed? -> File.write!(file, [output, "\n"])
      true -> :ok
    end
  rescue
    exception -> {:exit, {file, exception, __STACKTRACE__}}
  end
end
