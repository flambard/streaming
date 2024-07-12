defmodule MacroUtilsTest do
  use ExUnit.Case

  alias Streaming.MacroUtils

  test "get vars from binary pattern" do
    pattern = quote do: <<a, <<b::24>>::binary, a>> when a < 30
    assert [{:a, _, _}, {:b, _, _}] = MacroUtils.vars_from_binary_pattern(pattern)
  end
end
