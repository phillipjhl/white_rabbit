defmodule WhiteRabbit.Consumer.State do
  @moduledoc """
  Consumer State Struct for WhiteRabbit Consumer GenServers.

  This struct is used to store the state of the `WhiteRabbit.Consumer` GenServers so the callbacks
  can expect certain structure of items.
  """

  defstruct consumer_init_args: %{},
            state: %{
              channel: nil,
              queue: nil,
              consumer_tag: nil,
              processor: nil
            },
            backoff_agent_pid: nil

  @type t :: %__MODULE__{
          consumer_init_args: WhiteRabbit.Consumer.t(),
          state: %{
            channel: AMQP.Channel.t(),
            queue: String.t(),
            consumer_tag: String.t(),
            processor: WhiteRabbit.Processor.Config.t()
          },
          backoff_agent_pid: pid()
        }
end
