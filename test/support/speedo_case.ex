# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.SpeedoCase do
  @moduledoc """
  Helpers around testing Style rules.
  """
  use ExUnit.CaseTemplate

  using do
    quote do
      import unquote(__MODULE__), only: [assert_error: 2, refute_errors: 1, lint: 1]
    end
  end

  defmacro assert_error(code, check) do
    quote location: :keep, bind_quoted: [code: code, check: check] do
      errors = lint(code)

      if Enum.empty?(errors) and ExUnit.configuration()[:trace] do
        dbg(code)
        {ast, comments} = Styler.string_to_quoted_with_comments(code)
        dbg(ast)
        dbg(comments)
      end

      assert [%{check: ^check, message: m, line: l, file: f}] = errors
      assert m, "message was nil for #{check} in #{inspect(errors)}"
      assert l, "line was nil for #{check} in #{inspect(errors)}"
      assert f, "file was nil for #{check} in #{inspect(errors)}"
    end
  end

  def refute_errors(code) do
    assert [] = lint(code)
  end

  def lint(code) do
    code
    |> Styler.lint()
    |> List.flatten()
    |> Enum.reject(&is_nil/1)
  end
end
