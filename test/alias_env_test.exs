# Copyright 2025 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.AliasEnvTest do
  use ExUnit.Case, async: true

  import Styler.AliasEnv

  test "define" do
    {:__block__, [], ast} =
      quote do
        alias A.B
        alias C.D, as: X
      end

    env = define(ast)

    assert %{B: [:A, :B], X: [:C, :D]} == env
    assert %{B: [:M, :N, :B], X: [:C, :D]} == define(env, quote(do: alias(M.N.B)))
  end

  test "expand" do
    assert expand(%{B: [:A, :B], X: [:C, :D]}, [:B]) == [:A, :B]
    assert expand(%{B: [:A, :B], X: [:C, :D]}, [:B, :C, :D]) == [:A, :B, :C, :D]
    assert expand(%{B: [:A, :B], X: [:C, :D]}, [:Not, :Present]) == [:Not, :Present]
    assert expand(%{}, [:Hi]) == [:Hi]
  end

  test "expand_ast" do
    {_, _, aliases} =
      quote do
        alias A.B
        alias A.B.C
        alias A.B.C.D, as: X
      end

    ast =
      quote do
        A
        B
        C
        X
      end

    expected =
      quote do
        A
        A.B
        A.B.C
        A.B.C.D
      end

    assert aliases |> define() |> expand_ast(ast) == expected
  end
end
