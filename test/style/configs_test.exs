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
    {ast, _} = Styler.string_to_quoted_with_comments("import Config\n\nconfig :bar, boop: :baz")
    zipper = Styler.Zipper.zip(ast)

    for file <- ~w(dev.exs my_app.exs config.exs) do
      # :config? is private api, so don't be surprised if this has to change at some point
      assert {:cont, _, %{config?: true}} = Configs.run(zipper, %{file: "apps/foo/config/#{file}"})
      assert {:cont, _, %{config?: true}} = Configs.run(zipper, %{file: "config/#{file}"})
      assert {:cont, _, %{config?: true}} = Configs.run(zipper, %{file: "rel/overlay/#{file}"})
      assert {:halt, _, _} = Configs.run(zipper, %{file: file})
    end
  end

  test "orders configs stanzas" do
    # doesn't order when we haven't seen `import Config`, so this is something else that we don't understand
    assert_style """
    config :z, :x
    config :a, :b
    """

    # 1. orders `config/2,3` relative to each other
    # 2. lifts assignments above config blocks
    # 3. non assignment/config separate "config" blocks

    assert_style(
      """
      import Config
      dog_sound = :woof
      # z is best when configged w/ dog sounds
      # dog sounds ftw
      config :z, :x, dog_sound

      # this is my big c
      # comment i'd like to leave c
      # about c
      c = :c
      config :a, :b, c
      config :a, :c, :d
      config :a,
        a_longer_name: :a_longer_value,
        multiple_things: :that_could_all_fit_on_one_line_though

      # this is my big my_app
      # comment i'd like to leave my_app
      # about my_app
      my_app =
        :"dont_write_configs_like_this_yall_:("

      # this is my big your_app
      # comment i'd like to leave your_app
      # about your_app
      your_app = :not_again!
      config your_app, :dont_use_varrrrrrrrs
      config my_app, :nooooooooo
      import_config "my_config"

      cat_sound = :meow
      config :z, a: :meow
      a_sad_overwrite_that_will_be_hard_to_notice = :x
      config :a, :b, a_sad_overwrite_that_will_be_hard_to_notice
      """,
      """
      import Config

      dog_sound = :woof
      # z is best when configged w/ dog sounds
      # dog sounds ftw

      # this is my big c
      # comment i'd like to leave c
      # about c
      c = :c

      # this is my big my_app
      # comment i'd like to leave my_app
      # about my_app
      my_app =
        :"dont_write_configs_like_this_yall_:("

      # this is my big your_app
      # comment i'd like to leave your_app
      # about your_app
      your_app = :not_again!

      config :a, :b, c
      config :a, :c, :d

      config :a,
        a_longer_name: :a_longer_value,
        multiple_things: :that_could_all_fit_on_one_line_though

      config :z, :x, dog_sound

      config my_app, :nooooooooo

      config your_app, :dont_use_varrrrrrrrs

      import_config "my_config"

      cat_sound = :meow
      a_sad_overwrite_that_will_be_hard_to_notice = :x

      config :a, :b, a_sad_overwrite_that_will_be_hard_to_notice

      config :z, a: :meow
      """
    )
  end

  test "ignores things that look like config/1" do
    assert_style """
    import Config

    config :a, :b

    config(a)
    config :c, :d
    """
  end
end
