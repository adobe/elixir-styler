defmodule Styler.ConfigTest do
  use ExUnit.Case, async: false

  import Styler.Config

  test "no config is good times" do
    assert :ok = set!([])
  end

  describe "alias_lifting_exclude" do
    test "takes singletons atom" do
      set!(alias_lifting_exclude: Foo)
      assert %MapSet{} = excludes = get(:lifting_excludes)
      assert :Foo in excludes
      refute Foo in excludes

      set!(alias_lifting_exclude: :Foo)
      assert %MapSet{} = excludes = get(:lifting_excludes)
      assert :Foo in excludes
    end

    test "list of atoms" do
      set!(alias_lifting_exclude: [Foo, :Bar])
      assert %MapSet{} = excludes = get(:lifting_excludes)
      assert :Foo in excludes
      refute Foo in excludes
      assert :Bar in excludes
    end

    test "raises on non-atom inputs" do
      assert_raise RuntimeError, ~r"Expected an atom", fn ->
        set!(alias_lifting_exclude: ["Bar"])
      end
    end
  end
end
