# Copyright 2025 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Mix.Tasks.Styler.InlineAttrs do
  @shortdoc "EXPERIMENTAL: inlines module attributes with literal values that are only referenced once"
  @moduledoc """
  WARNING: EXPERIMENTAL | Inlines module attributes that are only referenced once in their module.

  **This is known to create invalid code.** It's far from perfect.
  It can still be a helpful first step in refactoring though.

  Formats files with a currently hard-coded length of 122.

  **Usage**:

      mix styler.inline_attrs <file_path> [... additional file paths]

      mix styler.inline_attrs path/to/my/file.ex path/to/another_file.ex

  ## Example:

      # This ...
      defmodule A do
        @non_literal_attr Application.compile_env(...)
        @literal_value_with_only_one_reference :my_key

        def foo(), do: Application.get_env(:my_app, @literal_value_with_only_one_reference)
      end

      # Becomes this
      defmodule A do
        @non_literal_attr Application.compile_env(...)

        def foo(), do: Application.get_env(:my_app, :my_key)
      end
  """
  use Mix.Task

  alias Styler.Zipper

  @impl Mix.Task
  def run(files) do
    for file <- files do
      {ast, comments} = file |> File.read!() |> Styler.string_to_ast(file)
      {{ast, _}, _} = ast |> Zipper.zip() |> Zipper.traverse_while(nil, &Styler.Style.InlineAttrs.run/2)
      File.write!(file, Styler.ast_to_string(ast, comments))
    end
  end
end
