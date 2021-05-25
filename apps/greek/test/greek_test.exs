defmodule GreekTest do
  use ExUnit.Case
  doctest Greek

  test "greets the world" do
    assert Greek.hello() == :world
  end
end
