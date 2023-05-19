# 0. wait, i think there's a better way to do this
food_widgets =
  widgets
  |> Enum.map(fn %{widget: widget} ->
    foo(widget)
  end)
  |> List.flatten()

# 1. oh no, i've broken the pipe rules! gotta fix it...
food_widgets =
  widgets
  |> Enum.flat_map(fn %{widget: widget} ->
    foo(widget)
  end)

# 2. cut the variable...
food_widgets =

  |> Enum.flat_map(fn %{widget: widget} ->
    foo(widget)
  end)

# 3. paste it as the first argument and add a comma
#   (is the comma its own step??)
food_widgets =

  |> Enum.flat_map(widgets, fn %{widget: widget} ->
    foo(widget)
  end)

# 4. delete the pipe and whitespace
food_widgets = Enum.flat_map(widgets, fn %{widget: widget} ->
    foo(widget)
  end)

# 5. multi-cursor delete the newlines and
#   (maybe?) leave the weird spacing to formatter
food_widgets = Enum.flat_map(widgets, fn %{widget: widget} ->    foo(widget)  end)

# 6. augh my file cant compile right now anyways,
#    and i cant stand looking at that weird spacing.
#    had to just fix it myself
food_widgets = Enum.flat_map(widgets, fn %{widget: widget} -> foo(widget) end)
