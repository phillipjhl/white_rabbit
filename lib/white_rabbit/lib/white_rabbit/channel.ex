defmodule WhiteRabbit.Channel do
  @moduledoc """
  WhiteRabbit AMQP channel GenServer.

  Starts an `%AMQP.Channel{}` process with the given `WhiteRabbit.Connection` GenServer and
  registers it to a `WhiteRabbit.ChannelRegistry` to allow other process to grab open amqp channels from the registry and use them.

  Backoff on failed channel open. Tries to re-open parent connection and open channel again.
  """

  use GenServer

  alias AMQP.{Channel}
  require Logger

  import WhiteRabbit.Core, only: [get_backoff: 1]

  defstruct name: :default,
            connection: nil,
            counter_agent: nil

  @typedoc """
    `%WhiteRabbit.Channel{}` struct that defines the nessecary config for creating channel GenServers.
  """
  @type t :: %__MODULE__{name: atom(), connection: atom(), counter_agent: pid()}

  def start_link(opts) do
    channel_config = Keyword.get(opts, :channel, %__MODULE__{})
    %__MODULE__{name: name} = channel_config

    GenServer.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(arg) do
    # Start backoff agent
    {:ok, pid} = Agent.start_link(fn -> 1 end)

    channel_config = Keyword.get(arg, :channel, %__MODULE__{}) |> Map.put(:counter_agent, pid)
    module = Keyword.get(arg, :module, WhiteRabbit)

    init_config = :persistent_term.get({WhiteRabbit, module})
    channel_registry = init_config.channel_registry

    start_amqp_channel(channel_config, channel_registry)
  end

  @impl true
  def handle_info(:start_channel, {_channel, config, channel_registry}) do
    # Start a channel under this process.
    case start_amqp_channel(config, channel_registry) do
      {:ok, {%AMQP.Channel{} = active_channel, config, channel_registry}} ->
        {:noreply, {active_channel, config, channel_registry}}

      _ ->
        {:noreply, {nil, config, channel_registry}}
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
          {:ok, {AMQP.Channel.t(), __MODULE__.t(), atom()}} | {:ok, {nil, __MODULE__.t(), atom()}}
  def start_amqp_channel(
        %__MODULE__{name: name, connection: connection} = channel_config,
        channel_registry \\ WhiteRabbit.ChannelRegistry
      ) do
    # Get Genserver state and use connection
    # Then open a channel on the active connection
    with {%AMQP.Connection{} = active_conn, _conn_config} <-
           GenServer.call(connection, :get_connection_state, :infinity),
         {:ok, %AMQP.Channel{} = channel} <- Channel.open(active_conn) do
      Logger.debug("Opened Channel: #{inspect(channel)}")

      # Register to channel registry
      # This process will be removed from the Registry if it dies or is killed by the channel supervisor
      {:ok, _} = Registry.register(channel_registry, connection, channel)
      Logger.info("Registerd Channel to #{channel_registry} with key: #{inspect(connection)}")

      # put channel in state
      {:ok, {channel, channel_config, channel_registry}}
    else
      _ ->
        backoff = get_backoff(channel_config.counter_agent)
        retry = 5000 + 1000 * backoff
        Logger.error("Could not start channel: #{name}. Retrying in #{retry / 1000} seconds.")
        Process.send_after(self(), :start_channel, 5000 + 1000 * backoff)
        {:ok, {nil, channel_config, channel_registry}}
    end
  end
end
