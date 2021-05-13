defmodule WhiteRabbit.Connection do
  @moduledoc """
  Genserver to monitor one AMQP connection
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
  @type conn_opts :: [conn_opt()]

  @type t :: %__MODULE__{connection_name: atom(), conn_opts: keyword(), channels: list(map())}

  def start_link(%__MODULE__{connection_name: connection_name} = opts) do
    GenServer.start_link(__MODULE__, opts, name: connection_name)
  end

  @impl true
  def init(%__MODULE__{conn_opts: conn_opts}) do
    amqp_url = Keyword.get(conn_opts, :url, nil)
    options = Keyword.get(conn_opts, :options, nil)

    # If there are options use that, else use url string
    conn = if options, do: options, else: amqp_url

    case Connection.open(conn) do
      {:ok, %AMQP.Connection{pid: pid} = conn} ->
        # put conn in state
        Process.monitor(pid)
        {:ok, conn}

      {:error, error} ->
        {:stop, error}
    end
  end

  @impl true
  def handle_call(:get_connection_state, {_pid, _term}, state) do
    # Reply with current state, which is an %AMQP.Connection{}
    {:reply, state, state}
  end

  @impl true
  def handle_info(
        {:DOWN, _, :process, _pid, reason},
        state
      ) do
    Logger.warn(inspect(reason))
    # Trigger restart of connection GenServer from the Supervisor if AMQP connection is closed
    {:stop, :connection_down, state}
  end
end
