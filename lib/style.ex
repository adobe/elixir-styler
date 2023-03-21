# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style do
  @moduledoc """
  A Style takes AST and returns a transformed version of that AST.

  Because these transformations involve traversing trees (the "T" in "AST"), we wrap the AST in a structure
  called a Zipper to facilitate walking the trees.
  """

  alias Styler.Zipper

  @type command :: :cont | :skip | :halt

  @doc """
  `run` will be used with `Zipper.traverse_while/3`, meaning it will be executed on every node of the AST.

  You can skip traversing parts of the tree by returning a Zipper that's further along in the traversal, for example
  by calling `Zipper.skip(zipper)` to skip an entire subtree you know is of no interest to your Style.
  """
  @callback run(Zipper.zipper()) :: Zipper.zipper() | {command(), Zipper.zipper()}

  @doc false
  # this lets Styles optionally implement as though they're running inside of `Zipper.traverse`
  # or `Zipper.traverse_while` for finer-grained control
  def wrap_run(style) do
    fn zipper ->
      case style.run(zipper) do
        {next, {_, _} = _zipper} = command when next in ~w(cont halt skip)a -> command
        zipper -> {:cont, zipper}
      end
    end
  end
end
