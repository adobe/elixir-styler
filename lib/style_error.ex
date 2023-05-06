# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.StyleError do
  @moduledoc """
  Wraps errors raised by Styles during tree traversal.
  """
  defexception [:exception, :style, :file]

  def message(%{exception: exception, style: style, file: file}) do
    file = file && if file == :std, do: "stdin", else: Path.relative_to_cwd(file)
    style = style |> Module.split() |> List.last()

    """
    Error running style #{style} on #{file}
       Please consider opening an issue at: #{IO.ANSI.light_green()}https://github.com/adobe/elixir-styler/issues/new#{IO.ANSI.reset()}
    #{IO.ANSI.default_color()}#{Exception.format(:error, exception)}
    """
  end
end
