# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Style.CommentDirectivesTest do
  @moduledoc false
  use Styler.StyleCase, async: true

  describe "sort" do
    test "we dont just sort by accident" do
      assert_style "[:c, :b, :a]"
    end

    test "sorts lists of atoms" do
      assert_style(
        """
        # styler:sort
        [
          :c,
          :b,
          :c,
          :a
        ]
        """,
        """
        # styler:sort
        [
          :a,
          :b,
          :c,
          :c
        ]
        """
      )
    end

    test "sorts sigils" do
      assert_style("# styler:sort\n~w|c a b|", "# styler:sort\n~w|a b c|")

      assert_style(
        """
        # styler:sort
        ~w(
          a
          long
          list
          of
          static
          values
        )
        """,
        """
        # styler:sort
        ~w(
          a
          list
          long
          of
          static
          values
        )
        """
      )
    end

    test "assignments" do
      assert_style(
        """
        # styler:sort
        my_var =
          ~w(
            a
            long
            list
            of
            static
            values
          )
        """,
        """
        # styler:sort
        my_var =
          ~w(
            a
            list
            long
            of
            static
            values
          )
        """
      )

      assert_style(
        """
        defmodule M do
          @moduledoc false
          # styler:sort
          @attr ~w(
              a
              long
              list
              of
              static
              values
            )
        end
        """,
        """
        defmodule M do
          @moduledoc false
          # styler:sort
          @attr ~w(
              a
              list
              long
              of
              static
              values
            )
        end
        """
      )
    end

    test "doesnt affect downstream nodes" do
      assert_style(
        """
        # styler:sort
        [:c, :a, :b]

        @country_codes ~w(
          po_PO
          en_US
          fr_CA
          ja_JP
        )
        """,
        """
        # styler:sort
        [:a, :b, :c]

        @country_codes ~w(
          po_PO
          en_US
          fr_CA
          ja_JP
        )
        """
      )
    end

    test "list of tuples" do
      # 2ples are represented as block literals while >2ples are created via `:{}`
      # decided the easiest way to handle this is to just use string representation for meow
      assert_style(
        """
        # styler:sort
        [
          {:styler, github: "adobe/elixir-styler"},
          {:ash, "~> 3.0"},
          {:fluxon, "~> 1.0.0", repo: :fluxon},
          {:phoenix_live_reload, "~> 1.2", only: :dev},
          {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
        ]
        """,
        """
        # styler:sort
        [
          {:ash, "~> 3.0"},
          {:fluxon, "~> 1.0.0", repo: :fluxon},
          {:phoenix_live_reload, "~> 1.2", only: :dev},
          {:styler, github: "adobe/elixir-styler"},
          {:tailwind, "~> 0.2", runtime: Mix.env() == :dev}
        ]
        """
      )
    end

    test "treats comments nicely" do
      assert_style("""
      # styler:sort
      [
        {:argon2_elixir, "~> 4.0"},
        {:phoenix, "~> 1.7"},
        {:cowboy, "~> 2.8", override: true},
        # There's a stream_body bug in Hackney 1.18.2, so don't upgrade to that.
        {:hackney, "1.18.1", override: true},
        {:styler, "~> 1.2", only: [:dev, :test], runtime: false},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},
        # ecto 3.12 overrides
        {:scrivener_ecto, github: "frameio/scrivener_ecto", override: true},
        {:vtc, github: "frameio/vtc-ex", override: true},
        # end ecto 3.12 overrides
        {:ecto, "~> 3.12"},
        {:ecto_sql, "~> 3.12"},
        {:httpoison, "~> 2.1", override: true},
        {:gen_stage, "~> 1.0", override: true},
        {:dialyxir, "~> 1.1", runtime: false},
        {:excoveralls, "~> 0.10", only: :test},
        {:telemetry, "~> 1.0", override: true},
        # We need to override because dataloader over-specifies its optional version spec
        # and it conflicts with opentelemetry_phoenix
        {:opentelemetry_process_propagator, "~> 0.3", override: true},
        {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
        {:junit_formatter, "~> 3.3", only: [:test]},
        {:stream_data, "~> 1.0", only: [:dev, :test]}
      ]

      # some other comment
      ""","""
      # styler:sort
      [
        {:argon2_elixir, "~> 4.0"},
        {:cowboy, "~> 2.8", override: true},
        {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
        {:dialyxir, "~> 1.1", runtime: false},
        # end ecto 3.12 overrides
        {:ecto, "~> 3.12"},
        {:ecto_sql, "~> 3.12"},
        {:excellent_migrations, "~> 0.1", only: [:dev, :test], runtime: false},
        {:excoveralls, "~> 0.10", only: :test},
        {:gen_stage, "~> 1.0", override: true},
        # There's a stream_body bug in Hackney 1.18.2, so don't upgrade to that.
        {:hackney, "1.18.1", override: true},
        {:httpoison, "~> 2.1", override: true},
        {:junit_formatter, "~> 3.3", only: [:test]},
        {:mix_audit, "~> 2.0", only: [:dev, :test], runtime: false},
        # We need to override because dataloader over-specifies its optional version spec
        # and it conflicts with opentelemetry_phoenix
        {:opentelemetry_process_propagator, "~> 0.3", override: true},
        {:phoenix, "~> 1.7"},
        # ecto 3.12 overrides
        {:scrivener_ecto, github: "frameio/scrivener_ecto", override: true},
        {:stream_data, "~> 1.0", only: [:dev, :test]},
        {:styler, "~> 1.2", only: [:dev, :test], runtime: false},
        {:telemetry, "~> 1.0", override: true},
        {:vtc, github: "frameio/vtc-ex", override: true}
      ]

      # some other comment
      """)
    end
  end
end
