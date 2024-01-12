defmodule Styler.Dictum do
  @moduledoc false

  def run(zipper, context) do
    run!(Styler.Zipper.node(zipper))
    {:cont, zipper, context}
  end

  @definer ~w(def defp defmacro defmacrop defguard defguardp)a
  defp run!({def, _, [{name, _, _} | _]}) when def in @definer do
    name = to_string(name)
    # Credo.Check.Readability.FunctionNames
    unless snake_case?(name), do: raise "#{def} #{name} is not snake case"
    # Credo.Check.Readability.PredicateFunctionNames
    cond do
      String.starts_with?(name, "is_") && String.ends_with?(name, "?") ->

        raise "#{def} #{name} wow choose `?` or `is_`, you monster"
      def in ~w(def defp)a and String.starts_with?(name, "is_") ->

        raise "#{def} #{name} is invalid -- use `?` not `is_` for defs"
      def in ~w(defmacro defmacrop defguard defguardp)a and String.ends_with?(name, "?") ->

        raise "#{def} #{name}: use `is_*` not `*?` for things that can be used in guards"
    end
  end

  # Credo.Check.Readability.ImplTrue
  defp run!({:@, _, [{:impl, _, [true]}]}), do: raise "@impl true not allowed"
  # Credo.Check.Readability.ModuleAttributeNames
  defp run!({:@, _, [{name, _, _}]}) do
    unless snake_case?(name), do: raise "@#{name} is not snake case"
  end
  # Credo.Check.Readability.ModuleNames
  defp run!({:defmodule, _, [{:__aliases__, _, aliases} | _]}) do
    name = Enum.map_join(aliases, ".", &to_string/1)
    unless pascal_case?(name), do: raise "defmodule #{name} is not pascal case"
  end

  # Credo.Check.Readability.StringSigils
  defp run!({:__block__, [delimiter: ~s|"| | _], [string]}) do
    if string =~ ~r/".*".*"/, do: raise "use a sigil for #{inspect(string)}, it has too many quotes"
  end
  # Credo.Check.Readability.VariableNames
  defp run!({name, _, nil}) do
    # probably get false positives here if people haven't run their pipes thru first
    # also, when we start reporting multiple errors this'll need updating to only report at the place a var is created 🤔
    unless snake_case?(name), do: raise "#{name}: variables must be snake case"
  end
  # Credo.Check.Readability.WithCustomTaggedTuple
  defp run!({:<-, _, [{tag, _}, {tag, _}]}), do: raise "tagging tuples with things like #{tag} is known to be evil"
  #
  # def naughtyFun do
  #   raise "nooooo"
  # end

  defp snake_case?(name), do: to_string(name) =~ ~r/^[[:lower:]\d\_\!\?]+$/u
  defp pascal_case?(name), do: to_string(name) =~ ~r/^[A-Z][a-zA-Z0-9]*$/
end
