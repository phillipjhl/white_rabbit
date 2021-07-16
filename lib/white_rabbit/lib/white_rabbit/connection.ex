defmodule WhiteRabbit.Connection do
  @moduledoc """
  GenServer to open a `%AMQP.Connection{}` and monitors it to allow for `:stop` events and restarts from Supervisor.
  """

  use GenServer

  alias AMQP.{Connection}

  require Logger

  @enforce_keys [:connection_name, :conn_opts, :channels]
  defstruct connection_name: :default,
            conn_opts: [url: nil, options: []],
            channels: []

  @typedoc """
    ## URL

    The AMQP 0-9-1 connection string like: "amqp:quest:quest@localhost:5672/dev"

    See https://www.rabbitmq.com/uri-spec.html

    ## Options

    * `:username` - The name of a user registered with the broker (default
      `"guest"`)

    * `:password` - The password of user (default to `"guest"`)

    * `:virtual_host` - The name of a virtual host in the broker (defaults
      `"/"`)

    * `:host` - The hostname of the broker (default `"localhost"`)

    * `:port` - The port the broker is listening on (default `5672`)

    * `:channel_max` - The channel_max handshake parameter (default `0`)

    * `:frame_max` - The frame_max handshake parameter (defaults `0`)

    * `:heartbeat` - The hearbeat interval in seconds (defaults `10`)

    * `:connection_timeout` - The connection timeout in milliseconds (efaults
      `50000`)

    * `:ssl_options` - Enable SSL by setting the location to cert files
      (default `:none`)

    * `:client_properties` - A list of extra client properties to be sent to
      the server (default `[]`)

    * `:socket_options` - Extra socket options. These are appended to the
      default options. See http://www.erlang.org/doc/man/inet.html#setopts-2 and
      http://www.erlang.org/doc/man/gen_tcp.html#connect-4 for descriptions of
      the available options

    * `:auth_mechanisms` - A list of authentication of SASL authentication
      mechanisms to use. See
      https://www.rabbitmq.com/access-control.html#mechanisms and
      https://github.com/rabbitmq/rabbitmq-auth-mechanism-ssl for descriptions of
      the available options

    * `:name` - A human-readable string that will be displayed in the
      management UI. Connection names do not have to be unique and cannot be
      used as connection identifiers (default `:undefined`)
  """
  @type conn_opt :: {:url, String.t()} | {:options, keyword()}
  @typedoc """
  Keyword list of `conn_opt()` types. Provided to `WhiteRabbit.Connection` struct.

  Example
  ```
  [conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"]]
  ```
  """
  @type conn_opts :: [conn_opt()]

  @typedoc """
  %WhiteRabbit.Connection{} struct type, used for initial config and GenServer state.
  """
  @type t :: %__MODULE__{connection_name: atom(), conn_opts: keyword(), channels: list(map())}

  def start_link(%__MODULE__{connection_name: connection_name} = opts) do
    GenServer.start_link(__MODULE__, opts, name: connection_name)
  end

  @impl true
  def init(%__MODULE__{conn_opts: _conn_opts} = opts) do
    start_amqp_connection(opts)
  end

  @impl true
  def handle_call(:get_connection_state, {_pid, _term}, {conn, config} = state)
      when is_nil(conn) do
    # Retry connecting to amqp connection.
    # If succesful, send new connection state to caller.
    case start_amqp_connection(config) do
      {:ok, new_state} -> {:reply, new_state, new_state}
      _ -> {:reply, state, state}
    end
  end

  @impl true
  def handle_call(
        :get_connection_state,
        {_pid, _term},
        {%AMQP.Connection{} = _active_conn, _config} = state
      ) do
    # Reply with current state, which is {%AMQP.Connection{}, %WhiteRabbit.Connection{}}
    {:reply, state, state}
  end

  @impl true
  def handle_info(:start_connection, {_conn, config}) do
    # Start a connection under this process.
    case start_amqp_connection(config) do
      {:ok, {%AMQP.Connection{} = active_conn, config}} ->
        {:noreply, {active_conn, config}}

      _ ->
        Process.send_after(self(), :start_connection, 5000)
        {:noreply, {nil, config}}
    end
  end

  @impl true
  def handle_info(
        {:DOWN, _, :process, _pid, reason},
        state
      ) do
    Logger.warn("WhiteRabbit.Connection received :DOWN message. Reason: #{inspect(reason)}")
    # Trigger restart of connection GenServer from the Supervisor if AMQP connection is closed
    {:stop, :connection_down, state}
  end

  @doc """
  Tries to start an `%AMQP.Connection{}` with the passed config.

  Monitors the opened connection so the Genserver can shut itself down in the event of an unexpected close.
  (Management API force-close, CLI close, etc.)

  A {:ok, {_, _}} tuple is always returned so the Genserver will always start even if it cannot connect.
  """
  @spec start_amqp_connection(__MODULE__.t()) ::
          {:ok, {AMQP.Connection.t(), __MODULE__.t()}}
          | {:ok, {nil, __MODULE__.t()}}
  def start_amqp_connection(%__MODULE__{conn_opts: conn_opts} = opts) do
    amqp_url = Keyword.get(conn_opts, :url, nil)
    options = Keyword.get(conn_opts, :options, [])

    conn_name = Keyword.get(options, :name, Atom.to_string(opts.connection_name))
    options = Keyword.put(options, :name, conn_name)

    case Connection.open(amqp_url, options) do
      {:ok, %AMQP.Connection{pid: pid} = active_conn} ->
        # put conn in state
        Process.monitor(pid)
        Logger.info("Connected amqp connection with: #{inspect(amqp_url)} name: #{conn_name}")

        {:ok, {active_conn, opts}}

      {:error, error} ->
        Logger.error("Could not connect amqp connection with: #{inspect(error)}")

        {:ok, {nil, opts}}
    end
  end
end
