defmodule WhiteRabbitTest do
  use ExUnit.Case
  doctest WhiteRabbit

  test "process_name/2 returns correct atom" do
    assert WhiteRabbit.process_name("foo", :Bar) == :"Bar.foo"
    assert WhiteRabbit.process_name("Bar") == :"Elixir.WhiteRabbit.Bar"
  end
end
