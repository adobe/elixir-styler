defmodule Styler.ConfigIntegrationTest do
  use Styler.StyleCase, async: false

  alias Styler.Config

  setup do
    on_exit(fn -> Config.set([]) end)
  end

  test "`:alias_lifting_exclude` - collisions with configured modules" do
    Config.set(alias_lifting_exclude: ~w(C)a)

    assert_style """
    alias Foo.Bar

    A.B.C
    A.B.C
    """
  end

  @tag skip: Version.match?(System.version(), "< 1.17.0-dev")
  test "`:minimum_supported_elixir_version` and :timer config @ 1.17-dev" do
    Config.set(minimum_supported_elixir_version: "1.16.0")
    assert_style ":timer.minutes(60 * 4)"
    Config.set(minimum_supported_elixir_version: "1.17.0-dev")
    assert_style ":timer.hours(x)", "to_timeout(hour: x)"
  end
end
