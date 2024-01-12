# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler do
  @moduledoc """
  Styler is a formatter plugin with stronger opinions on code organization, multi-line defs and other code-style matters.
  """
  @behaviour Mix.Tasks.Format

  alias Styler.StyleError
  alias Styler.Zipper

  @styles [
    Styler.Style.ModuleDirectives,
    Styler.Style.Pipes,
    Styler.Style.SingleNode,
    Styler.Style.Defs,
    Styler.Style.Blocks,
    Styler.Style.Deprecations
  ]

  @doc false
  def style({ast, comments}, file, opts) do
    on_error = opts[:on_error] || :log
    zipper = Zipper.zip(ast)
    context = %{comments: comments, file: file}

    {{ast, _}, %{comments: comments}} =
      Enum.reduce(@styles, {zipper, context}, fn style, {zipper, context} ->
        try do
          Zipper.traverse_while(zipper, context, &style.run/2)
        rescue
          exception ->
            exception = StyleError.exception(exception: exception, style: style, file: file)

            if on_error == :log do
              error = Exception.format(:error, exception, __STACKTRACE__)
              Mix.shell().error("#{error}\n#{IO.ANSI.reset()}Skipping style and continuing on")
              {zipper, context}
            else
              reraise exception, __STACKTRACE__
            end
        end
      end)

    {ast, comments}
  end

  @impl Mix.Tasks.Format
  def features(_opts), do: [sigils: [], extensions: [".ex", ".exs"]]

  @impl Mix.Tasks.Format
  def format(input, formatter_opts, opts \\ []) do
    file = formatter_opts[:file]

    {ast, comments} =
      input
      |> string_to_quoted_with_comments(to_string(file))
      |> style(file, opts)

    quoted_to_string(ast, comments, formatter_opts)
  end

  @doc false
  # Wrap `Code.string_to_quoted_with_comments` with our desired options
  def string_to_quoted_with_comments(code, file \\ "nofile") when is_binary(code) do
    Code.string_to_quoted_with_comments!(code,
      literal_encoder: &__MODULE__.literal_encoder/2,
      token_metadata: true,
      unescape: false,
      file: file
    )
  end

  @doc false
  def literal_encoder(a, b), do: {:ok, {:__block__, b, [a]}}

  @doc false
  # Turns an ast and comments back into code, formatting it along the way.
  def quoted_to_string(ast, comments, formatter_opts \\ []) do
    opts = [{:comments, comments}, {:escape, false} | formatter_opts]
    {line_length, opts} = Keyword.pop(opts, :line_length, 122)

    formatted =
      ast
      |> Code.quoted_to_algebra(opts)
      |> Inspect.Algebra.format(line_length)

    IO.iodata_to_binary([formatted, ?\n])
  end
end
