# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler do
  @moduledoc false

  @doc """
  Wraps `Code.string_to_quoted_with_comments` with our desired options
  """
  def string_to_quoted_with_comments(code) when is_binary(code) do
    Code.string_to_quoted_with_comments!(code,
      literal_encoder: &__MODULE__.literal_encoder/2,
      token_metadata: true,
      unescape: false
    )
  end

  @doc false
  def literal_encoder(a, b), do: {:ok, {:__block__, b, [a]}}

  @doc """
  Turns an ast and comments back into code, formatting it along the way.
  """
  def quoted_to_string(ast, comments, formatter_opts \\ []) do
    opts = [{:comments, comments}, {:escape, false} | formatter_opts]
    {line_length, opts} = Keyword.pop(opts, :line_length, 122)

    ast
    |> Code.quoted_to_algebra(opts)
    |> Inspect.Algebra.format(line_length)
    |> IO.iodata_to_binary()
  end
end
