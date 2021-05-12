defmodule WhiteRabbit.Hole do
  @moduledoc """
  WhiteRabbit Supervisor that handles the main topology of WhiteRabbit and its children.

  This Supervisor tree is registered under the caller module name.
  """
  use Supervisor
  require Logger

  alias WhiteRabbit.PoolSupervisor

  def start_link({module, opts}) do
    Supervisor.start_link(__MODULE__, opts, name: module)
  end

  @impl true
  def init(arg) do
    name = Keyword.get(arg, :name, nil)
    additional_children = Keyword.get(arg, :children, [])
    # To Do: Create consumer and producer supervision tree
    additional_connections = Keyword.get(arg, :connections, [])

    connections =
      [
        %{
          connection_name: :whiterabbit_default_connection,
          conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
          channels: [
            %{
              name: :default_consumer_channel
            },
            %{
              name: :default_producer_channel
            },
            %{
              name: :default_rpc_channel
            }
          ]
        }
      ] ++ additional_connections

    children =
      [
        # RPC Req ETS

        # AMQP Channel Process Registry
        {Registry, [name: WhiteRabbit.ChannelRegistry, keys: :duplicate]},

        # WhiteRabbit connection super
        {PoolSupervisor, [connections: connections]}

        # WhiteRabbit consumer/producer super -> dynamic supers
      ] ++ additional_children

    Logger.info("Starting the WhiteRabbit.Hole")

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
