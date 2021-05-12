defmodule WhiteRabbit.Channel do
  use GenServer

  alias AMQP.{Channel, Connection}
  require Logger

  def start_link(%{name: name, connection: connection}) do
    GenServer.start_link(__MODULE__, %{name: name, connection: connection}, name: name)
  end

  @impl true
  def init(%{name: name, connection: connection}) do
    # Get Genserver state and use connection
    connection_state = GenServer.call(connection, :get_connection_state)

    case Channel.open(connection_state) do
      {:ok, channel} ->
        Logger.debug("Opened Channel: #{inspect(channel)}")

        # Register to WhiteRabbit.ChannelRegistry
        # This process will be removed from the Registry if it dies or is killed by the channel supervisor
        {:ok, _} = Registry.register(WhiteRabbit.ChannelRegistry, connection, channel)
        Logger.debug("Registerd Channel to WhiteRabbit.ChannelRegistry: #{inspect(connection)}")

        # put channel in state
        {:ok, channel}

      {:error, error} ->
        {:stop, error}

      _ ->
        {:stop, :unknown}
    end
  end
end
