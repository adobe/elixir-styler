# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ModuleDirectives.AliasLiftingTest do
  @moduledoc false
  use Styler.StyleCase, async: true

  test "lifts aliases in snippets" do
    assert_style(
      """
      A.B.C
      # z
      A.B.C
      """,
      """
      alias A.B.C

      C
      # z
      C
      """
    )
  end

  test "snippet with a single node" do
    assert_style(
      """
      # 0
      {
        # 1
        A.B.C,
        # 2
        A.B.C,
        # 3

        # 4
        "something so long that we keep this silly tuple split across multiple lines to recreate the issue at hand"
      }
      """,
      """
      alias A.B.C

      # 0
      {
        # 1
        C,
        # 2
        C,
        # 3

        # 4
        "something so long that we keep this silly tuple split across multiple lines to recreate the issue at hand"
      }
      """
    )

    assert_style(
      """
      {
        A.B.C,
        A.B.C,
      }
      """,
      """
      alias A.B.C

      {C, C}
      """
    )
  end

  test "lifts aliases repeated >=2 times from 3 deep" do
    assert_style(
      """
      defmodule A do
        @moduledoc false

        @spec bar :: A.B.C.t()
        def bar do
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false

        alias A.B.C

        @spec bar :: C.t()
        def bar do
          C.f()
        end
      end
      """
    )
  end

  test "lifts from nested modules" do
    assert_style(
      """
      defmodule A do
        @moduledoc false

        defmodule B do
          @moduledoc false

          A.B.C.f()
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false

        alias A.B.C

        defmodule B do
          @moduledoc false

          C.f()
          C.f()
        end
      end
      """
    )

    # this isn't exactly _desired_ behaviour but i don't see a real problem with it.
    # as long as we're deterministic that's alright. this... really should never happen in the real world.
    assert_style(
      """
      defmodule A do
        defmodule B do
          A.B.C.f()
          A.B.C.f()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false
        alias A.B.C

        defmodule B do
          @moduledoc false
          C.f()
          C.f()
        end
      end
      """
    )
  end

  test "only deploys new aliases in nodes _after_ the alias stanza" do
    assert_style(
      """
      defmodule Timely do
        use A.B.C
        def foo do
          A.B.C.bop
        end
        import A.B.C
        require A.B.C
      end
      """,
      """
      defmodule Timely do
        @moduledoc false
        use A.B.C

        import A.B.C

        alias A.B.C

        require C

        def foo do
          C.bop()
        end
      end
      """
    )
  end

  test "skips over quoted or odd aliases" do
    assert_style """
    alias Boop.Baz

    Some.unquote(whatever).Alias.bar()
    Some.unquote(whatever).Alias.bar()
    """
  end

  test "deep nesting of an alias" do
    assert_style(
      """
      alias Foo.Bar.Baz

      Baz.Bop.Boom.wee()
      Baz.Bop.Boom.wee()

      """,
      """
      alias Foo.Bar.Baz
      alias Foo.Bar.Baz.Bop.Boom

      Boom.wee()
      Boom.wee()
      """
    )
  end

  test "lifts in modules with only-child bodies" do
    assert_style(
      """
      defmodule A do
        def lift_me() do
          A.B.C.foo()
          A.B.C.baz()
        end
      end
      """,
      """
      defmodule A do
        @moduledoc false
        alias A.B.C

        def lift_me do
          C.foo()
          C.baz()
        end
      end
      """
    )
  end

  test "re-sorts requires after lifting" do
    assert_style(
      """
      defmodule A do
        require A.B.C
        require B

        A.B.C.foo()
      end
      """,
      """
      defmodule A do
        @moduledoc false
        alias A.B.C

        require B
        require C

        C.foo()
      end
      """
    )
  end

  test "two modules that seem to conflict but don't!" do
    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        A.B.C.foo(X.Y.A)
        A.B.C.bar()

        X.Y.A
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias A.B.C
        alias X.Y.A

        C.foo(A)
        C.bar()

        A
      end
      """
    )
  end

  test "if multiple lifts collide, lifts only one" do
    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        A.B.C.f()
        A.B.C.f()
        X.Y.C.f()
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias A.B.C

        C.f()
        C.f()
        X.Y.C.f()
      end
      """
    )

    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        A.B.C.f()
        X.Y.C.f()
        X.Y.C.f()
        A.B.C.f()
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias A.B.C

        C.f()
        X.Y.C.f()
        X.Y.C.f()
        C.f()
      end
      """
    )

    assert_style(
      """
      defmodule Foo do
        @moduledoc false

        X.Y.C.f()
        A.B.C.f()
        X.Y.C.f()
        A.B.C.f()
      end
      """,
      """
      defmodule Foo do
        @moduledoc false

        alias X.Y.C

        C.f()
        A.B.C.f()
        C.f()
        A.B.C.f()
      end
      """
    )
  end

  describe "comments stay put" do
    test "comments before alias stanza" do
      assert_style(
        """
        # Foo is my fave
        import Foo

        A.B.C.f()
        A.B.C.f()
        """,
        """
        # Foo is my fave
        import Foo

        alias A.B.C

        C.f()
        C.f()
        """
      )
    end

    test "comments after alias stanza" do
      assert_style(
        """
        # Foo is my fave
        require Foo

        A.B.C.f()
        A.B.C.f()
        """,
        """
        alias A.B.C
        # Foo is my fave
        require Foo

        C.f()
        C.f()
        """
      )
    end
  end

  describe "it doesn't lift" do
    test "collisions with configured modules" do
      Styler.Config.set(alias_lifting_exclude: ~w(C)a)

      assert_style """
      alias Foo.Bar

      A.B.C
      A.B.C
      """

      Styler.Config.set([])
    end

    test "collisions with std lib" do
      assert_style """
      defmodule DontYouDare do
        @moduledoc false

        My.Sweet.List.foo()
        My.Sweet.List.foo()
        IHave.MyOwn.Supervisor.init()
        IHave.MyOwn.Supervisor.init()
      end
      """
    end

    test "collisions with aliases" do
      for alias_c <- ["alias A.C", "alias A.B, as: C"] do
        assert_style """
        defmodule NuhUh do
          @moduledoc false

          #{alias_c}

          A.B.C.f()
          A.B.C.f()
        end
        """
      end
    end

    test "collisions with submodules" do
      assert_style """
      defmodule A do
        @moduledoc false

        A.B.C.f()

        defmodule C do
          @moduledoc false
          A.B.C.f()
        end

        A.B.C.f()
      end
      """
    end

    test "collisions with 3-deep one-off" do
      assert_style """
      defmodule Foo do
        @moduledoc false

        X.Y.Z.foo(A.B.X)

        A.B.X
      end
      """
    end

    test "when new alias being sorted in would change an existing alias" do
      assert_style(
        """
        defmodule Foo do
          @moduledoc false

          X.Y.Z.foo(A.B.X)
          X.Y.Z.bar()

          A.B.X
        end
        """,
        """
        defmodule Foo do
          @moduledoc false

          alias X.Y.Z

          Z.foo(A.B.X)
          Z.bar()

          A.B.X
        end
        """
      )
    end

    test "defprotocol, defmodule, or defimpl" do
      assert_style """
      defmodule No do
        @moduledoc false

        defprotocol A.B.C do
          :body
        end

        A.B.C.f()
      end
      """

      assert_style(
        """
        defmodule No do
          @moduledoc false

          defimpl A.B.C, for: A.B.C do
            :body
          end

          A.B.C.f()
          A.B.C.f()
        end
        """,
        """
        defmodule No do
          @moduledoc false

          alias A.B.C

          defimpl A.B.C, for: A.B.C do
            :body
          end

          C.f()
          C.f()
        end
        """
      )

      assert_style """
      defmodule No do
        @moduledoc false

        defmodule A.B.C do
          @moduledoc false
          :body
        end

        A.B.C.f()
      end
      """

      assert_style """
      defmodule No do
        @moduledoc false

        defimpl A.B.C, for: A.B.C do
          :body
        end

        A.B.C.f()
      end
      """
    end

    test "quoted sections" do
      assert_style """
      defmodule A do
        @moduledoc false
        defmacro __using__(_) do
          quote do
            A.B.C.f()
            A.B.C.f()
          end
        end
      end
      """
    end

    test "collisions with other callsites :(" do
      # if the last module of a list in an alias
      # is the first of any other
      # do not do the lift of either?
      assert_style """
      defmodule A do
        @moduledoc false

        foo
        |> Baz.Boom.bop()
        |> boop()

        Foo.Bar.Baz.bop()
        Foo.Bar.Baz.bop()
      end
      """

      assert_style """
      defmodule A do
        @moduledoc false

        Foo.Bar.Baz.bop()
        Foo.Bar.Baz.bop()

        foo
        |> Baz.Boom.bop()
        |> boop()
      end
      """
    end
  end
end
