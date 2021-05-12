defmodule WhiteRabbit.Connection do
  @moduledoc """
  Genserver to monitor one AMQP connection
  """

  use GenServer

  alias AMQP.{Channel, Connection}

  defstruct connection_name: :default,
            conn_opts: [url: nil, options: []]

  def start_link(%{connection_name: connection_name, conn_opts: _conn_opts} = opts) do
    GenServer.start_link(__MODULE__, opts, name: connection_name)
  end

  @impl true
  def init(%{connection_name: connection_name, conn_opts: conn_opts}) do
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
  def handle_call(:get_connection_state, {pid, term}, state) do
    # Reply with current state, which is an %AMQP.Connection{}
    {:reply, state, state}
  end

  @impl true
  def handle_info(
        {:DOWN, _, :process, pid, reason},
        state
      ) do
    # Trigger restart of connection GenServer from the Supervisor if AMQP connection is closed
    {:stop, :connection_down, state}
  end
end
