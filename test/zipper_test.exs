# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

# Branched from https://github.com/doorgan/sourceror/blob/main/test/zipper_test.exs
# See this issue for context on branching: https://github.com/doorgan/sourceror/issues/67
defmodule StylerTest.ZipperTest do
  use ExUnit.Case, async: true

  alias Styler.Zipper

  describe "zip/1" do
    test "creates a zipper from a term" do
      assert Zipper.zip(42) == {42, nil}
    end
  end

  describe "children/1" do
    test "returns the children for a node" do
      assert [1, 2, 3] |> Zipper.zip() |> Zipper.children() == [1, 2, 3]
      assert {:foo, [], [1, 2]} |> Zipper.zip() |> Zipper.children() == [1, 2]

      assert {{:., [], [:left, :right]}, [], [:arg]} |> Zipper.zip() |> Zipper.children() == [
               {:., [], [:left, :right]},
               :arg
             ]

      assert {:left, :right} |> Zipper.zip() |> Zipper.children() == [:left, :right]
    end
  end

  describe "replace_children/2" do
    test "2-tuples" do
      assert {1, 2} |> Zipper.zip() |> Zipper.replace_children([3, 4]) |> Zipper.node() == {3, 4}
    end

    test "lists" do
      assert [1, 2, 3] |> Zipper.zip() |> Zipper.replace_children([:a, :b, :c]) |> Zipper.node() == [:a, :b, :c]
    end

    test "unqualified calls" do
      assert {:foo, [], [1, 2]} |> Zipper.zip() |> Zipper.replace_children([:a, :b]) |> Zipper.node() ==
               {:foo, [], [:a, :b]}
    end

    test "qualified calls" do
      assert {{:., [], [1, 2]}, [], [3, 4]} |> Zipper.zip() |> Zipper.replace_children([:a, :b, :c]) |> Zipper.node() ==
               {:a, [], [:b, :c]}
    end
  end

  describe "node/1" do
    test "returns the node for a zipper" do
      assert Zipper.node(Zipper.zip(42)) == 42
    end
  end

  describe "down/1" do
    test "rips and tears the parent node" do
      assert [1, 2] |> Zipper.zip() |> Zipper.down() == {1, {[], {[1, 2], nil}, [2]}}
      assert {1, 2} |> Zipper.zip() |> Zipper.down() == {1, {[], {{1, 2}, nil}, [2]}}

      assert {:foo, [], [1, 2]} |> Zipper.zip() |> Zipper.down() ==
               {1, {[], {{:foo, [], [1, 2]}, nil}, [2]}}

      assert {{:., [], [:a, :b]}, [], [1, 2]} |> Zipper.zip() |> Zipper.down() ==
               {{:., [], [:a, :b]}, {[],{{{:., [], [:a, :b]}, [], [1, 2]}, nil}, [1, 2]}}
    end
  end

  describe "up/1" do
    test "reconstructs the previous parent" do
      assert [1, 2] |> Zipper.zip() |> Zipper.down() |> Zipper.up() == {[1, 2], nil}
      assert {1, 2} |> Zipper.zip() |> Zipper.down() |> Zipper.up() == {{1, 2}, nil}
      assert {:foo, [], [1, 2]} |> Zipper.zip() |> Zipper.down() |> Zipper.up() == {{:foo, [], [1, 2]}, nil}

      assert {{:., [], [:a, :b]}, [], [1, 2]} |> Zipper.zip() |> Zipper.down() |> Zipper.up() ==
               {{{:., [], [:a, :b]}, [], [1, 2]}, nil}
    end

    test "returns nil at the top level" do
      assert 42 |> Zipper.zip() |> Zipper.up() == nil
    end
  end

  describe "left/1 and right/1" do
    test "correctly navigate horizontally" do
      zipper = Zipper.zip([1, [2, 3], [[4, 5], 6]])

      assert zipper |> Zipper.down() |> Zipper.right() |> Zipper.right() |> Zipper.node() == [[4, 5], 6]
      assert zipper |> Zipper.down() |> Zipper.right() |> Zipper.right() |> Zipper.left() |> Zipper.node() == [2, 3]
    end

    test "return nil at the boundaries" do
      zipper = Zipper.zip([1, 2])

      assert zipper |> Zipper.down() |> Zipper.left() == nil
      assert zipper |> Zipper.down() |> Zipper.right() |> Zipper.right() == nil
    end
  end

  describe "rightmost/1" do
    test "returns the rightmost child" do
      assert [1, 2, 3, 4, 5] |> Zipper.zip() |> Zipper.down() |> Zipper.rightmost() |> Zipper.node() == 5
    end

    test "returns itself it already at the rightmost node" do
      assert [1, 2, 3, 4, 5]
             |> Zipper.zip()
             |> Zipper.down()
             |> Zipper.rightmost()
             |> Zipper.rightmost()
             |> Zipper.rightmost()
             |> Zipper.node() == 5

      assert [1, 2, 3]
             |> Zipper.zip()
             |> Zipper.rightmost()
             |> Zipper.rightmost()
             |> Zipper.node() == [1, 2, 3]
    end
  end

  describe "leftmost/1" do
    test "returns the leftmost child" do
      assert [1, 2, 3, 4, 5]
             |> Zipper.zip()
             |> Zipper.down()
             |> Zipper.right()
             |> Zipper.right()
             |> Zipper.leftmost()
             |> Zipper.node() == 1
    end

    test "returns itself it already at the leftmost node" do
      assert [1, 2, 3, 4, 5]
             |> Zipper.zip()
             |> Zipper.down()
             |> Zipper.leftmost()
             |> Zipper.leftmost()
             |> Zipper.leftmost()
             |> Zipper.node() == 1

      assert [1, 2, 3]
             |> Zipper.zip()
             |> Zipper.leftmost()
             |> Zipper.leftmost()
             |> Zipper.node() == [1, 2, 3]
    end
  end

  describe "next/1" do
    test "walks forward in depth-first pre-order" do
      zipper = Zipper.zip([1, [2, [3, 4]], 5])

      assert zipper |> Zipper.next() |> Zipper.next() |> Zipper.next() |> Zipper.next() |> Zipper.node() == [3, 4]

      assert zipper
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.node() == 5
    end

    test "returns nil after exhausting the tree" do
      zipper = Zipper.zip([1, [2, [3, 4]], 5])

      refute zipper
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()

      refute Zipper.next({42, nil})
    end
  end

  describe "prev/1" do
    test "walks backwards in depth-first pre-order" do
      zipper = Zipper.zip([1, [2, [3, 4]], 5])

      assert zipper
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.prev()
             |> Zipper.prev()
             |> Zipper.prev()
             |> Zipper.node() == [3, 4]
    end

    test "returns nil when it reaches past the top" do
      zipper = Zipper.zip([1, [2, [3, 4]], 5])

      assert zipper
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.next()
             |> Zipper.prev()
             |> Zipper.prev()
             |> Zipper.prev()
             |> Zipper.prev() == nil
    end
  end

  describe "skip/2" do
    test "returns a zipper to the next sibling while skipping subtrees" do
      zipper =
        Zipper.zip([
          {:foo, [], [1, 2, 3]},
          {:bar, [], [1, 2, 3]},
          {:baz, [], [1, 2, 3]}
        ])

      zipper = Zipper.down(zipper)

      assert Zipper.node(zipper) == {:foo, [], [1, 2, 3]}
      assert zipper |> Zipper.skip() |> Zipper.node() == {:bar, [], [1, 2, 3]}
      assert zipper |> Zipper.skip(:next) |> Zipper.node() == {:bar, [], [1, 2, 3]}
      assert zipper |> Zipper.skip() |> Zipper.skip(:prev) |> Zipper.node() == {:foo, [], [1, 2, 3]}
    end

    test "returns nil if no previous sibling is available" do
      zipper =
        Zipper.zip([
          {:foo, [], [1, 2, 3]}
        ])

      zipper = Zipper.down(zipper)

      assert Zipper.skip(zipper, :prev) == nil
      assert [7] |> Zipper.zip() |> Zipper.skip(:prev) == nil
    end

    test "returns nil if no next sibling is available" do
      zipper =
        Zipper.zip([
          {:foo, [], [1, 2, 3]}
        ])

      zipper = Zipper.down(zipper)

      refute Zipper.skip(zipper)
    end
  end

  describe "traverse/2" do
    test "traverses in depth-first pre-order" do
      zipper = Zipper.zip([1, [2, [3, 4], 5], [6, 7]])

      assert zipper
             |> Zipper.traverse(fn
               {x, m} when is_integer(x) -> {x * 2, m}
               z -> z
             end)
             |> Zipper.node() == [2, [4, [6, 8], 10], [12, 14]]
    end

    test "traverses a subtree in depth-first pre-order" do
      zipper = Zipper.zip([1, [2, [3, 4], 5], [6, 7]])

      assert zipper
             |> Zipper.down()
             |> Zipper.right()
             |> Zipper.traverse(fn
               {x, m} when is_integer(x) -> {x + 10, m}
               z -> z
             end)
             |> Zipper.root() == [1, [12, [13, 14], 15], [6, 7]]
    end
  end

  describe "traverse/3" do
    test "traverses in depth-first pre-order" do
      zipper = Zipper.zip([1, [2, [3, 4], 5], [6, 7]])

      {_, acc} = Zipper.traverse(zipper, [], &{&1, [Zipper.node(&1) | &2]})

      assert [
               [1, [2, [3, 4], 5], [6, 7]],
               1,
               [2, [3, 4], 5],
               2,
               [3, 4],
               3,
               4,
               5,
               [6, 7],
               6,
               7
             ] == Enum.reverse(acc)
    end

    test "traverses a subtree in depth-first pre-order" do
      zipper = Zipper.zip([1, [2, [3, 4], 5], [6, 7]])

      {_, acc} =
        zipper
        |> Zipper.down()
        |> Zipper.right()
        |> Zipper.traverse([], &{&1, [Zipper.node(&1) | &2]})

      assert [[2, [3, 4], 5], 2, [3, 4], 3, 4, 5] == Enum.reverse(acc)
    end
  end

  describe "traverse_while/2" do
    test "traverses in depth-first pre-order and skips branch" do
      zipper = Zipper.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      assert zipper
             |> Zipper.traverse_while(fn
               {[x | _], _} = z when rem(x, 2) != 0 -> {:skip, z}
               {[_ | _], _} = z -> {:cont, z}
               {x, m} -> {:cont, {x + 100, m}}
             end)
             |> Zipper.node() == [110, [120, [130, 131], [21, [32, 33]], [122, 123]]]
    end

    test "traverses in depth-first pre-order and halts on halt" do
      zipper = Zipper.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      assert zipper
             |> Zipper.traverse_while(fn
               {[x | _], _} = z when rem(x, 2) != 0 -> {:halt, z}
               {[_ | _], _} = z -> {:cont, z}
               {x, m} -> {:cont, {x + 100, m}}
             end)
             |> Zipper.node() == [110, [120, [130, 131], [21, [32, 33]], [22, 23]]]
    end

    test "traverses until end while always skip" do
      assert {_, nil} = [1] |> Zipper.zip() |> Zipper.traverse_while(fn z -> {:skip, z} end)
    end

    test "handles a zipper that isn't at the top" do
      zipper = {{:node, [], [:a, :b]}, :pre_existing_meta}

      assert {{{:node, [], [:a, :b]}, :pre_existing_meta}, :yay} =
               Zipper.traverse_while(zipper, :boo, fn
                 {:b, _} = zipper, :boo -> {:halt, zipper, :yay}
                 zipper, boo -> {:cont, zipper, boo}
               end)
    end
  end

  describe "traverse_while/3" do
    test "traverses in depth-first pre-order and skips branch" do
      zipper = Zipper.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      {_zipper, acc} =
        Zipper.traverse_while(
          zipper,
          [],
          fn
            {[x | _], _} = z, acc when rem(x, 2) != 0 -> {:skip, z, acc}
            {[_ | _], _} = z, acc -> {:cont, z, acc}
            {x, _} = z, acc -> {:cont, z, [x + 100 | acc]}
          end
        )

      assert acc == [123, 122, 131, 130, 120, 110]
    end

    test "traverses in depth-first pre-order and halts on halt" do
      zipper = Zipper.zip([10, [20, [30, 31], [21, [32, 33]], [22, 23]]])

      {_zipper, acc} =
        Zipper.traverse_while(
          zipper,
          [],
          fn
            {[x | _], _} = z, acc when rem(x, 2) != 0 -> {:halt, z, acc}
            {[_ | _], _} = z, acc -> {:cont, z, acc}
            {x, _} = z, acc -> {:cont, z, [x + 100 | acc]}
          end
        )

      assert acc == [131, 130, 120, 110]
    end

    test "traverses until end while always skip" do
      assert {_, nil} =
               [1]
               |> Zipper.zip()
               |> Zipper.traverse_while(nil, fn z, acc -> {:skip, z, acc} end)
               |> elem(0)
    end
  end

  describe "top/1" do
    test "returns the top zipper" do
      assert [1, [2, [3, 4]]] |> Zipper.zip() |> Zipper.next() |> Zipper.next() |> Zipper.next() |> Zipper.top() ==
               {[1, [2, [3, 4]]], nil}

      assert 42 |> Zipper.zip() |> Zipper.top() |> Zipper.top() |> Zipper.top() == {42, nil}
    end
  end

  describe "root/1" do
    test "returns the root node" do
      assert [1, [2, [3, 4]]] |> Zipper.zip() |> Zipper.next() |> Zipper.next() |> Zipper.next() |> Zipper.root() ==
               [1, [2, [3, 4]]]
    end
  end

  describe "replace/2" do
    test "replaces the current node" do
      assert [1, 2] |> Zipper.zip() |> Zipper.down() |> Zipper.replace(:a) |> Zipper.root() == [:a, 2]
    end
  end

  describe "update/2" do
    test "updates the current node" do
      assert [1, 2] |> Zipper.zip() |> Zipper.down() |> Zipper.update(fn x -> x + 50 end) |> Zipper.root() ==
               [51, 2]
    end
  end

  describe "remove/1" do
    test "removes the node and goes back to the previous zipper" do
      zipper = [1, [2, 3], 4] |> Zipper.zip() |> Zipper.down() |> Zipper.rightmost() |> Zipper.remove()

      assert Zipper.node(zipper) == 3
      assert Zipper.root(zipper) == [1, [2, 3]]

      assert [1, 2, 3]
             |> Zipper.zip()
             |> Zipper.next()
             |> Zipper.rightmost()
             |> Zipper.remove()
             |> Zipper.remove()
             |> Zipper.remove()
             |> Zipper.node() == []
    end

    test "raises when attempting to remove the root" do
      assert_raise ArgumentError, fn ->
        42 |> Zipper.zip() |> Zipper.remove()
      end
    end
  end

  describe "insert_left/2 and insert_right/2" do
    test "insert a sibling to the left or right" do
      assert [1, 2, 3]
             |> Zipper.zip()
             |> Zipper.down()
             |> Zipper.right()
             |> Zipper.insert_left(:left)
             |> Zipper.insert_right(:right)
             |> Zipper.root() == [1, :left, 2, :right, 3]
    end

    test "builds a new root node made of a block" do
      assert {42, {[:nope], {{:__block__, _, _}, nil}, []}} = 42 |> Zipper.zip() |> Zipper.insert_left(:nope)
      assert {42, {[], {{:__block__, _, _}, nil}, [:nope]}} = 42 |> Zipper.zip() |> Zipper.insert_right(:nope)
    end
  end

  describe "insert_child/2 and append_child/2" do
    test "add child nodes to the leftmost or rightmost side" do
      assert [1, 2, 3] |> Zipper.zip() |> Zipper.insert_child(:first) |> Zipper.append_child(:last) |> Zipper.root() == [
               :first,
               1,
               2,
               3,
               :last
             ]

      assert {:left, :right} |> Zipper.zip() |> Zipper.insert_child(:first) |> Zipper.root() ==
               {:{}, [],
                [
                  :first,
                  :left,
                  :right
                ]}

      assert {:left, :right} |> Zipper.zip() |> Zipper.append_child(:last) |> Zipper.root() ==
               {:{}, [],
                [
                  :left,
                  :right,
                  :last
                ]}

      assert {:foo, [], []} |> Zipper.zip() |> Zipper.insert_child(:first) |> Zipper.append_child(:last) |> Zipper.root() ==
               {:foo, [], [:first, :last]}

      assert {{:., [], [:a, :b]}, [], []}
             |> Zipper.zip()
             |> Zipper.insert_child(:first)
             |> Zipper.append_child(:last)
             |> Zipper.root() ==
               {{:., [], [:a, :b]}, [], [:first, :last]}
    end
  end

  describe "find/3" do
    test "finds a zipper with a predicate" do
      zipper = Zipper.zip([1, [2, [3, 4], 5]])

      assert zipper |> Zipper.find(fn x -> x == 4 end) |> Zipper.node() == 4
      assert zipper |> Zipper.find(:next, fn x -> x == 4 end) |> Zipper.node() == 4
    end

    test "returns nil if nothing was found" do
      zipper = Zipper.zip([1, [2, [3, 4], 5]])

      assert Zipper.find(zipper, fn x -> x == 9 end) == nil
      assert Zipper.find(zipper, :prev, fn x -> x == 9 end) == nil
    end

    test "finds a zipper with a predicate in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Zipper.zip()
        |> Zipper.next()
        |> Zipper.next()
        |> Zipper.next()
        |> Zipper.next()

      assert zipper |> Zipper.find(:prev, fn x -> x == 2 end) |> Zipper.node() == 2
    end

    test "returns nil if nothing was found in direction :prev" do
      zipper =
        [1, [2, [3, 4], 5]]
        |> Zipper.zip()
        |> Zipper.next()
        |> Zipper.next()
        |> Zipper.next()
        |> Zipper.next()

      assert Zipper.find(zipper, :prev, fn x -> x == 9 end) == nil
    end
  end
end
