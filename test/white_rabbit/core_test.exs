defmodule WhiteRabbit.CoreTest do
  use ExUnit.Case
  alias WhiteRabbit.Core

  test "uuid_tag returns a string of correct length" do
    tag = Core.uuid_tag(10)
    assert is_binary(tag)
    assert String.length(tag) >= 10
  end

  test "get_backoff increments agent value" do
    {:ok, pid} = Agent.start_link(fn -> 1 end)
    assert Core.get_backoff(pid) == 1
    assert Core.get_backoff(pid) == 2
    Agent.stop(pid)
  end

  test "get_channel returns error for unknown channel" do
    assert match?({:error, _}, Core.get_channel(:unknown))
  end
end
