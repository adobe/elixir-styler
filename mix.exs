# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.MixProject do
  use Mix.Project

  # Don't forget to bump the README when doing non-patch version changes
  @version "1.2.1"
  @url "https://github.com/adobe/elixir-styler"

  def project do
    [
      app: :styler,
      version: @version,
      elixir: "~> 1.15",
      start_permanent: Mix.env() == :prod,
      elixirc_paths: elixirc_paths(Mix.env()),
      deps: deps(),

      ## Hex
      package: package(),
      description: "A code-style enforcer that will just FIFY instead of complaining",

      # Docs
      name: "Styler",
      docs: docs()
    ]
  end

  defp elixirc_paths(:test), do: ["lib", "test/support"]
  defp elixirc_paths(_), do: ["lib"]

  def application, do: [extra_applications: [:logger]]

  defp deps do
    [
      {:ex_doc, "~> 0.31", runtime: false, only: :dev}
    ]
  end

  defp package do
    [
      maintainers: ["Matt Enlow", "Greg Mefford"],
      licenses: ["Apache-2.0"],
      links: %{"GitHub" => @url}
    ]
  end

  defp docs do
    [
      main: "readme",
      source_ref: "v#{@version}",
      source_url: @url,
      groups_for_extras: [
        Rewrites: ~r/docs/
      ],
      extra_section: "Docs",
      extras: [
        "CHANGELOG.md": [title: "Changelog"],
        "docs/styles.md": [title: "Basic Styles"],
        "docs/deprecations.md": [title: "Deprecated Elixirisms"],
        "docs/pipes.md": [title: "Pipe Chains"],
        "docs/control_flow_macros.md": [title: "Control Flow Macros (if, case, ...)"],
        "docs/mix_configs.md": [title: "Mix Configs (config/*.exs)"],
        "docs/module_directives.md": [title: "Module Directives (use, alias, ...)"],
        "docs/credo.md": [title: "Styler & Credo"],
        "README.md": [title: "Styler"]
      ]
    ]
  end
end
