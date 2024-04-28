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
      assert {:cont, _, %{config?: true}} = Configs.run(zipper, %{file: "rel/overlays/#{file}"})
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
    assert_style(
      """
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
      """,
      enable: :configs
    )
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
      """,
      enable: :configs
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

    test "simple case" do
      assert_style(
        """
        import Config

        config :a, 1
        config :a, 4
        # comment
        # b comment
        config :b, 1
        config :b, 2
        config :a, 2
        config :a, 3
        """,
        """
        import Config

        config :a, 1
        config :a, 2
        config :a, 3
        config :a, 4
        # comment
        # b comment
        config :b, 1
        config :b, 2
        """,
        enable: :configs
      )
    end

    test "complicated comments" do
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
          # Multiline comment
          # comment in a block
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
          # Multiline comment
          # comment in a block
          multiple_things: :that_could_all_fit_on_one_line_though

        # z is best when configged w/ dog sounds
        # dog sounds ftw
        config :z, :x, dog_sound

        config my_app, :nooooooooo

        config your_app, :dont_use_varrrrrrrrs

        import_config "my_config"

        cat_sound = :meow
        a_sad_overwrite_that_will_be_hard_to_notice = :x

        config :a, :b, a_sad_overwrite_that_will_be_hard_to_notice

        config :z, a: :meow
        """,
        enable: :configs
      )
    end

    test "comments, more nuanced" do
      assert_style(
        """
        # start config
        # import
        import Config

        # random noise

        config :c,
          # ca
          ca: :ca,
          # cb 1
          # cb 2
          cb: :cb,
          cc: :cc,
          # cd
          cd: :cd

        # yeehaw
        config :b, :yeehaw, :meow
        config :b, :apples, :oranges
        config :b,
          a: :b,
          # bcd
          c: :d,
          e: :f

        # some junk after b, idk

        config :a,
          # aa
          aa: :aa,
          # ab 1
          # ab 2
          ab: :ab,
          ac: :ac,
          # ad
          ad: :cd

        # end of config
        """,
        """
        # start config
        # import
        import Config

        # random noise

        config :a,
          # aa
          aa: :aa,
          # ab 1
          # ab 2
          ab: :ab,
          ac: :ac,
          # ad
          ad: :cd

        config :b, :apples, :oranges

        # yeehaw
        config :b, :yeehaw, :meow

        config :b,
          a: :b,
          # bcd
          c: :d,
          e: :f

        config :c,
          # some junk after b, idk

          # ca
          ca: :ca,
          # cb 1
          # cb 2
          cb: :cb,
          cc: :cc,
          # cd
          cd: :cd

        # end of config
        """,
        enable: :configs
      )
    end
  end
end
