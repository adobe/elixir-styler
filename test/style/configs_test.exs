# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ConfigsTest do
  @moduledoc false
  use Styler.StyleCase, async: true, filename: "config/config.exs"

  alias Styler.Style.Configs

  test "only runs on exs files in config folders" do
    {ast, _} = Styler.string_to_quoted_with_comments "import Config\n\nconfig :bar, boop: :baz"
    zipper = Styler.Zipper.zip(ast)

    for file <- ~w(dev.exs my_app.exs config.exs) do
      # :config? is private api, so don't be surprised if this has to change at some point
      assert {:cont, _, %{config?: true}} = Configs.run(zipper, %{file: "apps/foo/config/#{file}"})
      assert {:cont, _, %{config?: true}} = Configs.run(zipper, %{file: "config/#{file}"})
      assert {:halt, _, _} = Configs.run(zipper, %{file: file})
    end
  end

  describe "config sorting" do

  end

  describe "" do

  end
end
