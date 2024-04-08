# Copyright 2024 Adobe. All rights reserved.
# This file is licensed to you under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License. You may obtain a copy
# of the License at http://www.apache.org/licenses/LICENSE-2.0

# Unless required by applicable law or agreed to in writing, software distributed under
# the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
# OF ANY KIND, either express or implied. See the License for the specific language
# governing permissions and limitations under the License.

defmodule Styler.Config do
  @moduledoc false
  @key __MODULE__

  @stdlib MapSet.new(~w(
    Access Agent Application Atom Base Behaviour Bitwise Code Date DateTime Dict Ecto Enum Exception
    File Float GenEvent GenServer HashDict HashSet Integer IO Kernel Keyword List
    Macro Map MapSet Module NaiveDateTime Node Oban OptionParser Path Port Process Protocol
    Range Record Regex Registry Set Stream String StringIO Supervisor System Task Time Tuple URI Version
  )a)

  def set(config) do
    :persistent_term.get(@key)
    :ok
  rescue
    ArgumentError -> set!(config)
  end

  def set!(config) do
    excludes =
      config[:alias_lifting_exclude]
      |> List.wrap()
      |> MapSet.new(fn
        atom when is_atom(atom) ->
          case to_string(atom) do
            "Elixir." <> rest -> String.to_atom(rest)
            _ -> atom
          end

        other ->
          raise "Expected an atom for `alias_lifting_exclude`, got: #{inspect(other)}"
      end)
      |> MapSet.union(@stdlib)

    :persistent_term.put(@key, %{
      lifting_excludes: excludes
    })
  end

  def get(key) do
    @key
    |> :persistent_term.get()
    |> Map.fetch!(key)
  end
end
