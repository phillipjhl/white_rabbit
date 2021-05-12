defmodule WhiteRabbit.ChannelSupervisor do
  @moduledoc """
  Supervisor of multiple AMQP Channels
  """

  use Supervisor

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  def init(%{connection: connection, channels: channels}) do
    channel_child_specs =
      Enum.map(channels, fn channel ->
        # All register to main Channel Process Registry
        %{
          id: channel.name,
          start:
            {WhiteRabbit.Channel, :start_link, [%{connection: connection, name: channel.name}]}
        }
      end)

    Supervisor.init(channel_child_specs, strategy: :one_for_one)
  end
end
