# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.ModuleDirectivesTest do
  @moduledoc false
  use Styler.StyleCase, async: true

  describe "defmodule features" do
    test "handles module with no directives" do
      assert_style("""
      defmodule Test do
        def foo, do: :ok
      end
      """)
    end

    test "handles dynamically generated modules" do
      assert_style("""
      Enum.each(testing_list, fn test_item ->
        defmodule test_item do
        end
      end)
      """)
    end

    test "module with single child" do
      assert_style(
        """
        defmodule ATest do
          alias Foo.{A, B}
        end
        """,
        """
        defmodule ATest do
          alias Foo.A
          alias Foo.B
        end
        """
      )
    end

    test "adds moduledoc" do
      assert_style(
        """
        defmodule A do
        end

        defmodule B do
          defmodule C do
          end
        end

        defmodule Bar do
          alias Bop

          :ok
        end

        defmodule DocsOnly do
          @moduledoc "woohoo"
        end

        defmodule Foo do
          use Bar
        end

        defmodule Foo do
          alias Foo.{Bar, Baz}
        end
        """,
        """
        defmodule A do
          @moduledoc false
        end

        defmodule B do
          @moduledoc false
          defmodule C do
            @moduledoc false
          end
        end

        defmodule Bar do
          @moduledoc false
          alias Bop

          :ok
        end

        defmodule DocsOnly do
          @moduledoc "woohoo"
        end

        defmodule Foo do
          @moduledoc false
          use Bar
        end

        defmodule Foo do
          @moduledoc false
          alias Foo.Bar
          alias Foo.Baz
        end
        """
      )
    end

    test "skips keyword defmodules" do
      assert_style("defmodule Foo, do: use(Bar)")
    end

    test "doesn't add moduledoc to modules of specific names" do
      for verboten <- ~w(Test Mixfile Controller Endpoint Repo Router Socket View HTML JSON) do
        assert_style("""
        defmodule A.B.C#{verboten} do
          @shortdoc "Don't change me!"
        end
        """)
      end
    end

    test "groups directives in order" do
      assert_style(
        """
        defmodule Foo do
          @behaviour Lawful
          require A
          alias A

          use B

          def c(x), do: y

          import C
          @behaviour Chaotic
          @doc "d doc"
          def d do
            alias X
            alias H

            alias Z
            import Ecto.Query
            X.foo()
          end
          @shortdoc "it's pretty short"
          import A
          alias C
          alias D

          require C
          require B

          use A

          alias C
          alias A

          @moduledoc "README.md"
                     |> File.read!()
                     |> String.split("<!-- MDOC !-->")
                     |> Enum.fetch!(1)
        end
        """,
        """
        defmodule Foo do
          @shortdoc "it's pretty short"
          @moduledoc "README.md"
                     |> File.read!()
                     |> String.split("<!-- MDOC !-->")
                     |> Enum.fetch!(1)
          @behaviour Chaotic
          @behaviour Lawful

          use B
          use A

          import A
          import C

          alias A
          alias C
          alias D

          require A
          require B
          require C

          def c(x), do: y

          @doc "d doc"
          def d do
            import Ecto.Query

            alias H
            alias X
            alias Z

            X.foo()
          end
        end
        """
      )
    end
  end

  describe "strange parents!" do
    test "anon function" do
      assert_style("fn -> alias A.{C, B} end", """
      fn ->
        alias A.B
        alias A.C
      end
      """)
    end

    test "quote do with one child" do
      assert_style(
        """
        quote do
          alias A.{C, B}
        end
        """,
        """
        quote do
          alias A.B
          alias A.C
        end
        """
      )
    end

    test "quote do with multiple children" do
      assert_style("""
      quote do
        import A
        import B
      end
      """)
    end
  end

  describe "directive sort/dedupe/expansion" do
    test "handles a lonely lonely directive" do
      assert_style("import Foo")
    end

    test "sorts, dedupes & expands alias/require/import while respecting groups" do
      for d <- ~w(alias require import) do
        assert_style(
          """
          #{d} D
          #{d} A.{B}
          #{d} A.{
            A,
            B,
            C
          }
          #{d} A.B

          #{d} B
          #{d} A
          """,
          """
          #{d} A
          #{d} A.A
          #{d} A.B
          #{d} A.C
          #{d} B
          #{d} D
          """
        )
      end
    end

    test "expands __MODULE__" do
      assert_style(
        """
        alias __MODULE__.{B.D, A}
        """,
        """
        alias __MODULE__.A
        alias __MODULE__.B.D
        """
      )
    end

    test "expands use but does not sort it" do
      assert_style(
        """
        use D
        use A
        use A.{
          C,
          B
        }
        import F
        """,
        """
        use D
        use A
        use A.C
        use A.B

        import F
        """
      )
    end

    test "interwoven directives w/o the context of a module" do
      assert_style(
        """
        @type foo :: :ok
        alias D
        alias A.{B}
        require A.{
          A,
          C
        }
        alias B
        alias A
        """,
        """
        alias A
        alias A.B
        alias B
        alias D

        require A.A
        require A.C

        @type foo :: :ok
        """
      )
    end

    test "respects as" do
      assert_style("""
      alias Foo.Asset
      alias Foo.Project.Loaders, as: ProjectLoaders
      alias Foo.ProjectDevice.Loaders, as: ProjectDeviceLoaders
      alias Foo.User.Loaders
      """)
    end
  end

  describe "with comments..." do
    test "moving aliases up through non-directives doesn't move comments up" do
      assert_style(
        """
        defmodule Foo do
          # mdf
          @moduledoc false
          # B
          alias B

          # foo
          def foo do
            # ok
            :ok
          end
          # C
          alias C
          # A
          alias A
        end
        """,
        """
        defmodule Foo do
          # mdf
          @moduledoc false
          alias A
          # B
          alias B
          alias C

          # foo
          def foo do
            # ok
            :ok
          end

          # C
          # A
        end
        """
      )
    end
  end
end
