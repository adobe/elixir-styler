# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.ConfigTest do
  use ExUnit.Case, async: false

  import Styler.Config

  setup do
    on_exit(fn -> set([]) end)
  end

  test "initialize" do
    assert :ok = initialize([])
  end

  describe "alias_lifting_exclude" do
    test "takes singletons atom" do
      set(alias_lifting_exclude: Foo)
      assert %MapSet{} = excludes = get(:lifting_excludes)
      assert :Foo in excludes
      refute Foo in excludes

      set(alias_lifting_exclude: :Foo)
      assert %MapSet{} = excludes = get(:lifting_excludes)
      assert :Foo in excludes
    end

    test "list of atoms" do
      set(alias_lifting_exclude: [Foo, :Bar])
      assert %MapSet{} = excludes = get(:lifting_excludes)
      assert :Foo in excludes
      refute Foo in excludes
      assert :Bar in excludes
    end

    test "raises on non-atom inputs" do
      assert_raise RuntimeError, ~r"Expected an atom", fn ->
        set(alias_lifting_exclude: ["Bar"])
      end
    end
  end

  describe "minimum_supported_elixir_version" do
    test "can be nil/unset" do
      set(minimum_supported_elixir_version: nil)
      assert is_nil(get(:minimum_supported_elixir_version))
      set([])
      assert is_nil(get(:minimum_supported_elixir_version))
    end

    test "parses semvers" do
      set(minimum_supported_elixir_version: "1.15.0")
      assert get(:minimum_supported_elixir_version) == Version.parse!("1.15.0")
    end

    test "kabooms for UX" do
      for weird <- ["1.15", "wee"] do
        assert_raise Version.InvalidVersionError, fn -> set(minimum_supported_elixir_version: weird) end
      end

      assert_raise ArgumentError, ~r/must be a string/, fn -> set(minimum_supported_elixir_version: 1.15) end
    end
  end

  test "version_compatible?" do
    set(minimum_supported_elixir_version: nil)
    assert version_compatible?(Version.parse!("100.0.0"))
    set(minimum_supported_elixir_version: "1.15.0")
    assert version_compatible?(Version.parse!("1.14.0"))
    assert version_compatible?(Version.parse!("1.15.0"))
    refute version_compatible?(Version.parse!("1.16.0"))
  end
end
