defmodule WhiteRabbit.Consumer.State do
  @moduledoc """
  Genserver State Struct for Aggie Rabbit Consumers
  """

  defstruct consumer_init_args: %{},
            state: %{
              channel: nil,
              queue: nil,
              consumer_tag: nil,
              processor: nil
            },
            backoff_agent_pid: nil
end
