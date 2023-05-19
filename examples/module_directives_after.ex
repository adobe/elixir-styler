defmodule ModuleDirectivesExample do
  @moduledoc File.read!("README.md")
  @behaviour MyBehaviour

  use AMacro

  import X
  import Y

  alias A
  alias B.D
  alias B.E
  alias C

  require B
  require C

  def id(x), do: x
end
