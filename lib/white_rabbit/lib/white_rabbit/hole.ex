defmodule WhiteRabbit.Hole do
  @moduledoc """
  WhiteRabbit Supervisor that handles the main topology of WhiteRabbit and its children.

  This Supervisor tree is registered under the caller module name.

  Defaults to two connections and two channels per connection. Max is 10 connections.
  """
  use Supervisor
  require Logger

  alias WhiteRabbit.{PoolSupervisor, Connection, Fluffle, RPC, Core}

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
    additional_connections = Keyword.get(arg, :connections, [])
    rpc_enabled = Keyword.get(arg, :rpc_enabled, true)

    connections =
      [
        %Connection{
          connection_name: :whiterabbit_rpc_conn,
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
        # AMQP Channel Process Registry, channels are registered under connection_name atoms
        {Registry, [name: WhiteRabbit.ChannelRegistry, keys: :duplicate]},

        # WhiteRabbit connection super
        {PoolSupervisor, [connections: connections]},

        # WhiteRabbit consumer/producer super -> dynamic supers
        {Fluffle, []}
      ] ++ additional_children ++ [configure_rpc_topology(rpc_enabled, arg)]

    Logger.info("Starting the #{name}")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def configure_rpc_topology(enabled, arg) do
    if enabled do
      reply_id = Core.uuid_tag()

      # Get config or use default
      rpc_config =
        Keyword.get(arg, :rpc_config, %{
          service_consumer: %WhiteRabbit.Consumer{
            connection_name: :whiterabbit_rpc_conn,
            name: "Aggie.RPC.Receiver",
            exchange: "suzerain.rpcs.exchange",
            queue: "aggie.rpcs",
            binding_keys: ["aggie.rpcs"],
            error_queue: false,
            processor: %WhiteRabbit.Processor.Config{module: RPC, function: :handle_rpc_message!}
          },
          replies_consumer: %WhiteRabbit.Consumer{
            connection_name: :whiterabbit_rpc_conn,
            name: "Aggie.RPC.Replies",
            exchange: "amq.direct",
            exchange_type: :direct,
            queue: "aggie.rpcs.replies.#{reply_id}",
            queue_opts: [auto_delete: true, durable: false, exclusive: true],
            binding_keys: ["#{reply_id}"],
            error_queue: false,
            processor: %WhiteRabbit.Processor.Config{module: RPC, function: :return_rpc_message!}
          },
          service_name: "aggie"
        })

      %{
        service_consumer: service_consumer,
        replies_consumer: replies_consumer,
        service_name: service_name
      } = rpc_config

      rpc_children = [
        # RPC ETS Table
        {WhiteRabbit.RPC.ProcessStore, [reply_id: reply_id, service_name: service_name]},

        # RPC Requests Registry
        {Registry, [name: RPCRequestRegistry, keys: :unique]},

        # RPC Service Consumer
        %{
          id: service_consumer.name,
          start: {WhiteRabbit.Consumer, :start_link, [service_consumer]}
        },

        # RPC Replies Consumer
        %{
          id: replies_consumer.name,
          start: {WhiteRabbit.Consumer, :start_link, [replies_consumer]}
        }
      ]

      # Supervisor Map
      %{
        id: WhiteRabbit.RPC.Supervisor,
        start: {Supervisor, :start_link, [rpc_children, [strategy: :one_for_one]]}
      }
    end
  end
end
