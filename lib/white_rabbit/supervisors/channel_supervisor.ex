defmodule WhiteRabbit.ChannelSupervisor do
  @moduledoc """
  Supervisor of multiple AMQP Channels.

  Each child is a `WhiteRabbit.Channel` GenServer started with a `:one_for_one` strategy.

  This Supervisor should be started under a `WhiteRabbit.PoolSupervisor` that also supervises one `WhiteRabbit.Connection` that will be
  used for all the children channels in the amqp connection pool.

  Channel Pool layout:

  ```
       ChannelSupervisor
        /      |      \
  Channel   Channel   Channel
  ```
  """

  use Supervisor

  alias WhiteRabbit.{Channel}

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  def init(arg) do
    connection = Keyword.get(arg, :connection, nil)
    channels = Keyword.get(arg, :channels, [])
    module = Keyword.get(arg, :module, WhiteRabbit)

    channel_child_specs =
      Enum.map(channels, fn channel ->
        # All channels will register to main Channel Process Registry
        channel_name = module.process_name("#{channel.name}")

        %{
          id: channel_name,
          start:
            {WhiteRabbit.Channel, :start_link,
             [[module: module, channel: %Channel{connection: connection, name: channel.name}]]}
        }
      end)

    Supervisor.init(channel_child_specs, strategy: :one_for_one)
  end
end
