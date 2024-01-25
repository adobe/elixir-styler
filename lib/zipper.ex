# Copyright 2023 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

# Branched from https://github.com/doorgan/sourceror/blob/main/lib/sourceror/zipper.ex,
# see this issue for context on branching: https://github.com/doorgan/sourceror/issues/67

# Initial implementation Copyright (c) 2021 dorgandash@gmail.com, licenced under Apache 2.0
defmodule Styler.Zipper do
  @moduledoc """
  Implements a Zipper for the Elixir AST based on Gérard Huet [Functional pearl: the
  zipper](https://www.st.cs.uni-saarland.de/edu/seminare/2005/advanced-fp/docs/huet-zipper.pdf) paper and
  Clojure's `clojure.zip` API.

  A zipper is a data structure that represents a location in a tree from the
  perspective of the current node, also called *focus*. It is represented by a
  2-tuple where the first element is the focus and the second element is the
  metadata/context. The metadata is `nil` when the focus is the topmost node
  """
  import Kernel, except: [node: 1]

  @type tree :: Macro.t()

  @opaque path :: %{
            l: [tree],
            ptree: zipper,
            r: [tree]
          }

  @type zipper :: {tree, path | nil}
  @type t :: zipper
  @type command :: :cont | :skip | :halt

  @doc """
  Returns a list of children of the node.
  """
  @spec children(zipper) :: [tree]
  def children({{form, _, args}, _}) when is_atom(form) and is_list(args), do: args
  def children({{form, _, args}, _}) when is_list(args), do: [form | args]
  def children({{left, right}, _}), do: [left, right]
  def children({list, _}) when is_list(list), do: list
  def children({_, _}), do: []

  @doc """
  Returns a new node, given an existing node and new children.
  """
  @spec replace_children(tree, [tree]) :: tree
  def replace_children({form, meta, _}, children) when is_atom(form), do: {form, meta, children}
  def replace_children({_form, meta, args}, [first | rest]) when is_list(args), do: {first, meta, rest}
  def replace_children({_, _}, [left, right]), do: {left, right}
  def replace_children({_, _}, children), do: {:{}, [], children}
  def replace_children(list, children) when is_list(list), do: children

  @doc """
  Creates a zipper from a tree node.
  """
  @spec zip(tree) :: zipper
  def zip(term), do: {term, nil}

  @doc """
  Walks the zipper all the way up and returns the top zipper.
  """
  @spec top(zipper) :: zipper
  def top({_, nil} = zipper), do: zipper
  def top(zipper), do: zipper |> up() |> top()

  @doc """
  Walks the zipper all the way up and returns the root node.
  """
  @spec root(zipper) :: tree
  def root(zipper), do: zipper |> top() |> node()

  @doc """
  Returns the node at the zipper.
  """
  @spec node(zipper) :: tree
  def node({tree, _}), do: tree

  @doc """
  Returns the zipper of the leftmost child of the node at this zipper, or
  nil if no there's no children.
  """
  @spec down(zipper) :: zipper | nil
  def down(zipper) do
    case children(zipper) do
      [] -> nil
      [first | rest] -> {first, %{ptree: zipper, l: [], r: rest}}
    end
  end

  @doc """
  Returns the zipper of the parent of the node at this zipper, or nil if at the
  top.
  """
  @spec up(zipper) :: zipper | nil
  def up({_, nil}), do: nil

  def up({tree, meta}) do
    children = Enum.reverse(meta.l, [tree | meta.r])
    {parent, parent_meta} = meta.ptree
    {replace_children(parent, children), parent_meta}
  end

  @doc """
  Returns the zipper of the left sibling of the node at this zipper, or nil.
  """
  @spec left(zipper) :: zipper | nil
  def left({tree, %{l: [ltree | l], r: r} = meta}), do: {ltree, %{meta | l: l, r: [tree | r]}}
  def left(_), do: nil

  @doc """
  Returns the leftmost sibling of the node at this zipper, or itself.
  """
  @spec leftmost(zipper) :: zipper
  def leftmost({tree, %{l: [_ | _] = l} = meta}) do
    [leftmost | r] = Enum.reverse(l, [tree | meta.r])
    {leftmost, %{meta | l: [], r: r}}
  end

  def leftmost(zipper), do: zipper

  @doc """
  Returns the zipper of the right sibling of the node at this zipper, or nil.
  """
  @spec right(zipper) :: zipper | nil
  def right({tree, %{r: [rtree | r]} = meta}), do: {rtree, %{meta | r: r, l: [tree | meta.l]}}
  def right(_), do: nil

  @doc """
  Returns the rightmost sibling of the node at this zipper, or itself.
  """
  @spec rightmost(zipper) :: zipper
  def rightmost({tree, %{r: [_ | _] = r} = meta}) do
    [rightmost | l] = Enum.reverse(r, [tree | meta.l])
    {rightmost, %{meta | l: l, r: []}}
  end

  def rightmost(zipper), do: zipper

  @doc """
  Replaces the current node in the zipper with a new node.
  """
  @spec replace(zipper, tree) :: zipper
  def replace({_, meta}, tree), do: {tree, meta}

  @doc """
  Replaces the current node in the zipper with the result of applying `fun` to
  the node.
  """
  @spec update(zipper, (tree -> tree)) :: zipper
  def update({tree, meta}, fun), do: {fun.(tree), meta}

  @doc """
  Removes the node at the zipper, returning the zipper that would have preceded
  it in a depth-first walk.
  """
  @spec remove(zipper) :: zipper
  def remove({_, nil}), do: raise(ArgumentError, message: "Cannot remove the top level node.")
  def remove({_, %{l: [left | rest]} = meta}), do: prev_down({left, %{meta | l: rest}})
  def remove({_, %{ptree: {parent, parent_meta}, r: children}}), do: {replace_children(parent, children), parent_meta}

  @doc """
  Inserts the item as the left sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  @spec insert_left(zipper, tree) :: zipper
  def insert_left({_, nil}, _), do: raise(ArgumentError, message: "Can't insert siblings at the top level.")
  def insert_left({tree, meta}, child), do: {tree, %{meta | l: [child | meta.l]}}

  @doc """
  Inserts many siblings to the left.

  Equivalent to

      Enum.reduce(siblings, zipper, &Zipper.insert_left(&2, &1))
  """
  @spec prepend_siblings(zipper, [tree]) :: zipper
  def prepend_siblings({_, nil}, _), do: raise(ArgumentError, message: "Can't insert siblings at the top level.")
  def prepend_siblings({tree, meta}, siblings), do: {tree, %{meta | l: Enum.reverse(siblings, meta.l)}}

  @doc """
  Inserts the item as the right sibling of the node at this zipper, without
  moving. Raises an `ArgumentError` when attempting to insert a sibling at the
  top level.
  """
  @spec insert_right(zipper, tree) :: zipper
  def insert_right({_, nil}, _), do: raise(ArgumentError, message: "Can't insert siblings at the top level.")
  def insert_right({tree, meta}, child), do: {tree, %{meta | r: [child | meta.r]}}

  @doc """
  Inserts many siblings to the right.

  Equivalent to

      Enum.reduce(siblings, zipper, &Zipper.insert_right(&2, &1))
  """
  @spec insert_siblings(zipper, [tree]) :: zipper
  def insert_siblings({_, nil}, _), do: raise(ArgumentError, message: "Can't insert siblings at the top level.")
  def insert_siblings({tree, meta}, siblings), do: {tree, %{meta | r: siblings ++ meta.r}}

  @doc """
  Inserts the item as the leftmost child of the node at this zipper,
  without moving.
  """
  def insert_child({tree, meta}, child), do: {do_insert_child(tree, child), meta}

  defp do_insert_child({form, meta, args}, child) when is_list(args), do: {form, meta, [child | args]}
  defp do_insert_child(list, child) when is_list(list), do: [child | list]
  defp do_insert_child({left, right}, child), do: {:{}, [], [child, left, right]}

  @doc """
  Inserts the item as the rightmost child of the node at this zipper,
  without moving.
  """
  def append_child({tree, meta}, child), do: {do_append_child(tree, child), meta}

  defp do_append_child({form, meta, args}, child) when is_list(args), do: {form, meta, args ++ [child]}
  defp do_append_child(list, child) when is_list(list), do: list ++ [child]
  defp do_append_child({left, right}, child), do: {:{}, [], [left, right, child]}

  @doc """
  Returns the following zipper in depth-first pre-order.
  """
  @spec next(zipper) :: zipper | nil
  def next(zipper), do: down(zipper) || skip(zipper)

  @doc """
  Returns the zipper of the right sibling of the node at this zipper, or the
  next zipper when no right sibling is available.

  This allows to skip subtrees while traversing the siblings of a node.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.

  If no right/left sibling is available, this function returns the same value as
  `next/1`/`prev/1`.

  The function `skip/1` behaves like the `:skip` in `traverse_while/2` and
  `traverse_while/3`.
  """
  @spec skip(zipper, direction :: :next | :prev) :: zipper | nil
  def skip(zipper, direction \\ :next)
  def skip(zipper, :next), do: right(zipper) || next_up(zipper)
  def skip(zipper, :prev), do: left(zipper) || prev_up(zipper)

  defp next_up(zipper) do
    if parent = up(zipper), do: right(parent) || next_up(parent)
  end

  defp prev_up(zipper) do
    if parent = up(zipper), do: left(parent) || prev_up(parent)
  end

  @doc """
  Returns the previous zipper in depth-first pre-order. If it's already at
  the end, it returns nil.
  """
  @spec prev(zipper) :: zipper | nil
  def prev(zipper) do
    if left = left(zipper), do: prev_down(left), else: up(zipper)
  end

  defp prev_down(zipper) do
    if down = down(zipper), do: down |> rightmost() |> prev_down(), else: zipper
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node.

  If the zipper is not at the top, just the subtree will be traversed.

  The function must return a zipper.
  """
  @spec traverse(zipper, (zipper -> zipper)) :: zipper
  def traverse({_tree, nil} = zipper, fun) do
    do_traverse(zipper, fun)
  end

  def traverse({tree, meta}, fun) do
    {updated, _meta} = do_traverse({tree, nil}, fun)
    {updated, meta}
  end

  defp do_traverse(zipper, fun) do
    zipper = fun.(zipper)
    if next = next(zipper), do: do_traverse(next, fun), else: top(zipper)
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator.

  If the zipper is not at the top, just the subtree will be traversed.
  """
  @spec traverse(zipper, term, (zipper, term -> {zipper, term})) :: {zipper, term}
  def traverse({_tree, nil} = zipper, acc, fun) do
    do_traverse(zipper, acc, fun)
  end

  def traverse({tree, meta}, acc, fun) do
    {{updated, _meta}, acc} = do_traverse({tree, nil}, acc, fun)
    {{updated, meta}, acc}
  end

  defp do_traverse(zipper, acc, fun) do
    {zipper, acc} = fun.(zipper, acc)
    if next = next(zipper), do: do_traverse(next, acc, fun), else: {top(zipper), acc}
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node.

  The traversing will continue if the function returns `{:cont, zipper}`,
  skipped for `{:skip, zipper}` and halted for `{:halt, zipper}`

  If the zipper is not at the top, just the subtree will be traversed.

  The function must return a zipper.
  """
  @spec traverse_while(zipper, (zipper -> {command, zipper})) :: zipper
  def traverse_while({_tree, nil} = zipper, fun) do
    do_traverse_while(zipper, fun)
  end

  def traverse_while({tree, meta}, fun) do
    {updated, _meta} = do_traverse_while({tree, nil}, fun)
    {updated, meta}
  end

  defp do_traverse_while(zipper, fun) do
    case fun.(zipper) do
      {:cont, zipper} -> if next = next(zipper), do: do_traverse_while(next, fun), else: top(zipper)
      {:skip, zipper} -> if skipped = skip(zipper), do: do_traverse_while(skipped, fun), else: top(zipper)
      {:halt, zipper} -> top(zipper)
    end
  end

  @doc """
  Traverses the tree in depth-first pre-order calling the given function for
  each node with an accumulator.

  The traversing will continue if the function returns `{:cont, zipper, acc}`,
  skipped for `{:skip, zipper, acc}` and halted for `{:halt, zipper, acc}`

  If the zipper is not at the top, just the subtree will be traversed.
  """
  @spec traverse_while(zipper, term, (zipper, term -> {command, zipper, term})) :: {zipper, term}
  def traverse_while({_tree, nil} = zipper, acc, fun) do
    do_traverse_while(zipper, acc, fun)
  end

  def traverse_while({tree, meta}, acc, fun) do
    {{updated, _meta}, acc} = do_traverse_while({tree, nil}, acc, fun)
    {{updated, meta}, acc}
  end

  defp do_traverse_while(zipper, acc, fun) do
    case fun.(zipper, acc) do
      {:cont, zipper, acc} -> if next = next(zipper), do: do_traverse_while(next, acc, fun), else: {top(zipper), acc}
      {:skip, zipper, acc} -> if skip = skip(zipper), do: do_traverse_while(skip, acc, fun), else: {top(zipper), acc}
      {:halt, zipper, acc} -> {top(zipper), acc}
    end
  end

  @doc """
  Returns a zipper to the node that satisfies the predicate function, or `nil`
  if none is found.

  The optional second parameters specifies the `direction`, defaults to
  `:next`.
  """
  @spec find(zipper, direction :: :prev | :next, predicate :: (tree -> any)) :: zipper | nil
  def find({tree, _} = zipper, direction \\ :next, predicate)
      when direction in [:next, :prev] and is_function(predicate, 1) do
    if predicate.(tree) do
      zipper
    else
      zipper = if direction == :next, do: next(zipper), else: prev(zipper)
      zipper && find(zipper, direction, predicate)
    end
  end

  @doc "Traverses `zipper`, returning true when `fun.(Zipper.node(zipper))` is truthy, or false otherwise"
  @spec any?(zipper, (tree -> term)) :: boolean()
  def any?({_, _} = zipper, fun) when is_function(fun, 1) do
    zipper
    |> traverse_while(false, fn {tree, _} = zipper, _ ->
      # {nil, nil} optimizes to not go back to the top of the zipper on a hit
      if fun.(tree), do: {:halt, {nil, nil}, true}, else: {:cont, zipper, false}
    end)
    |> elem(1)
  end
end
