defmodule WhiteRabbit.ChannelSupervisor do
  @moduledoc """
  Supervisor of multiple AMQP Channels

  Channel Pool layout:

       ChannelSupervisor
        /      |      \
       /       |       \
  Channel   Channel   Channel

  """

  use Supervisor

  alias WhiteRabbit.{Channel}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  def init(%{connection: connection, channels: channels}) do
    channel_child_specs =
      Enum.map(channels, fn channel ->
        # All channels will register to main Channel Process Registry
        %{
          id: channel.name,
          start:
            {WhiteRabbit.Channel, :start_link,
             [%Channel{connection: connection, name: channel.name}]}
        }
      end)

    Supervisor.init(channel_child_specs, strategy: :one_for_one)
  end
end
