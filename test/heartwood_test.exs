defmodule HeartwoodTest do
  use ExUnit.Case
  doctest Heartwood

  test "greets the world" do
    assert Heartwood.hello() == :world
  end
end
