defmodule ModuleDirectivesExample do
  require C
  alias C
  alias B.{ D,  E }
  @moduledoc "README.md" |> File.read!()
  def id(x), do: x
  alias A
  alias C

  use AMacro

  import Y
  import X
  alias C
  @behaviour MyBehaviour

  require B
end
