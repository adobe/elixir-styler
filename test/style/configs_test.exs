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

  test "doesn't sort when no import config" do
    assert_style """
    config :z, :x, :c
    config :a, :b, :c
    """
  end

  test "simple case" do
    assert_style """
    import Config

    config :z, :x, :c
    config :a, :b, :c
    config :y, :x, :z
    config :a, :c, :d
    """,
    """
    import Config

    config :a, :b, :c
    config :a, :c, :d

    config :y, :x, :z

    config :z, :x, :c
    """
  end

  test "more complicated" do
    assert_style(
      """
      import Config
      dog_sound = :woof
      config :z, :x, dog_sound

      c = :c
      config :a, :b, c
      config :a, :c, :d
      config :a,
        a_longer_name: :a_longer_value,
        multiple_things: :that_could_all_fit_on_one_line_though

      my_app =
        :"dont_write_configs_like_this_yall_:("

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
      c = :c

      my_app =
        :"dont_write_configs_like_this_yall_:("

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

  describe "playing nice with comments" do
    test "lets you leave comments in large stanzas" do
      assert_style """
      import Config

      config :a, B, :c

      config :a,
        b: :c,
        # d is here
        d: :e
      """
    end
  end
end
