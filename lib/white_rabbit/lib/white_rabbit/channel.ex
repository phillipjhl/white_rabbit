defmodule WhiteRabbit.Channel do
  @moduledoc """
  WhiteRabbit channel GenServer. Starts an `%AMQP.Channel{}` process with the given `WhiteRabbit.Connection` GenServer and
  registers it to a `WhiteRabbit.ChannelRegistry` to allow other process to grab open amqp channels from the registry and use them.

  Backoff on failed channel open. Tries to re-open parent connection and open channel again.
  """

  use GenServer

  alias AMQP.{Channel}
  require Logger

  import WhiteRabbit.Core

  defstruct name: :default,
            connection: nil,
            counter_agent: nil

  @typedoc """
    `%WhiteRabbit.Channel{}` struct that defines the nessecary config for creating channel GenServers.`
  """
  @type t :: %__MODULE__{name: atom(), connection: atom(), counter_agent: pid()}

  def start_link(%__MODULE__{name: name, connection: connection}) do
    GenServer.start_link(__MODULE__, %__MODULE__{name: name, connection: connection}, name: name)
  end

  @impl true
  def init(arg) do
    # Start backoff agent
    {:ok, pid} = Agent.start_link(fn -> 1 end)

    arg = Map.put(arg, :counter_agent, pid)

    start_amqp_channel(arg)
  end

  @impl true
  def handle_info(:start_channel, {channel, config}) do
    # Start a channel under this process.
    case start_amqp_channel(config) do
      {:ok, {%AMQP.Channel{} = active_channel, config}} ->
        {:noreply, {active_channel, config}}

      _ ->
        {:noreply, {nil, config}}
    end
  end

  @doc """
  Start an `%AMQP.Channel{}` process with the given config connection.

  Calls the WhiteRabbit.Connection Genserver registered under the connection atom to get the connection state and pid.

  If succussful, will try to open a `%AMQP.Channel{}` on the connection and then register the channel to a supervised registry.

  If a `nil` connection is returned, then retry opening the parent connection and this channel.

  The retry backoff is in the form of `5000 + 1000 * current_backoff_number`

  Always return a `{:ok, {_, _}}` tuple so the GenServer will always start.
  """
  @spec start_amqp_channel(__MODULE__.t()) ::
          {:ok, {AMQP.Channel.t(), __MODULE__.t()}} | {:ok, {nil, __MODULE__.t()}}
  def start_amqp_channel(%__MODULE__{name: name, connection: connection} = channel_config) do
    # Get Genserver state and use connection
    # Then open a channel on the active connection
    with {%AMQP.Connection{} = active_conn, conn_config} <-
           GenServer.call(connection, :get_connection_state, :infinity),
         {:ok, %AMQP.Channel{} = channel} <- Channel.open(active_conn) do
      Logger.debug("Opened Channel: #{inspect(channel)}")

      # Register to WhiteRabbit.ChannelRegistry
      # This process will be removed from the Registry if it dies or is killed by the channel supervisor
      {:ok, _} = Registry.register(WhiteRabbit.ChannelRegistry, connection, channel)
      Logger.info("Registerd Channel to WhiteRabbit.ChannelRegistry: #{inspect(connection)}")

      # put channel in state
      {:ok, {channel, channel_config}}
    else
      _ ->
        backoff = get_backoff(channel_config.counter_agent)
        retry = 5000 + 1000 * backoff
        Logger.error("Could not start channel: #{name}. Retrying in #{retry / 1000} seconds.")
        Process.send_after(self(), :start_channel, 5000 + 1000 * backoff)
        {:ok, {nil, channel_config}}
    end
  end
end
