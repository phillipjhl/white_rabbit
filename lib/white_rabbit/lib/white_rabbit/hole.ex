defmodule WhiteRabbit.Hole do
  @moduledoc """
  WhiteRabbit Supervisor that handles the main topology of WhiteRabbit and its children.

  This Supervisor tree is registered under the caller module name.

  Defaults to two connections and two channels per connection. Max is 10 connections.
  """
  use Supervisor
  require Logger

  alias WhiteRabbit.{PoolSupervisor, Connection, Fluffle}

  @type hole_option :: {:name, term()} | {:children, list()} | {:connections, [Connection.t()]}
  @type hole_args :: [hole_option()]

  def start_link({module, opts}) do
    opts = opts |> Keyword.put(:name, module)
    Supervisor.start_link(__MODULE__, opts, name: module)
  end

  @impl true
  @spec init(hole_args()) :: {:ok, tuple()}
  def init(arg) do
    name = Keyword.get(arg, :name, __MODULE__)
    additional_children = Keyword.get(arg, :children, [])
    # To Do: Create consumer and producer supervision tree
    additional_connections = Keyword.get(arg, :connections, [])

    connections =
      [
        %Connection{
          connection_name: :whiterabbit_default_connection,
          conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
          channels: [
            %{
              name: :default_consumer_channel
            },
            %{
              name: :default_producer_channel
            }
          ]
        },
        %Connection{
          connection_name: :whiterabbit_rpc_connection,
          conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
          channels: [
            %{
              name: :rpc_consumer_channel
            },
            %{
              name: :rpc_producer_channel
            }
          ]
        }
      ] ++ additional_connections

    children =
      [
        # RPC Req ETS

        # AMQP Channel Process Registry, channels are registered under connection_name atoms
        {Registry, [name: WhiteRabbit.ChannelRegistry, keys: :duplicate]},

        # WhiteRabbit connection super
        {PoolSupervisor, [connections: connections]},

        # WhiteRabbit consumer/producer super -> dynamic supers
        {Fluffle, []}
      ] ++ additional_children

    Logger.info("Starting the WhiteRabbit.Hole")

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
