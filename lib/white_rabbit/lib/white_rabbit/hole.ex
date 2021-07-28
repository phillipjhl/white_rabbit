defmodule WhiteRabbit.Hole do
  @moduledoc """
  WhiteRabbit Supervisor that handles the main topology of WhiteRabbit and its children.

  This Supervisor tree is registered under the caller module name.
  """
  use Supervisor
  require Logger

  alias WhiteRabbit.{PoolSupervisor, Connection, Fluffle, RPC, Core}

  @type hole_option ::
          {:name, term()}
          | {:children, list()}
          | {:connections, [Connection.t()]}
          | {:startup_consumers, [{term(), Consumer.t()}]}
  @type hole_args :: [hole_option()]

  def start_link({module, opts}) do
    opts = opts |> Keyword.put(:name, module)
    Supervisor.start_link(__MODULE__, opts, name: module)
  end

  @impl true
  @spec init(hole_args()) :: {:ok, tuple()}
  def init(arg) do
    module = Keyword.get(arg, :name, WhiteRabbit)
    additional_children = Keyword.get(arg, :children, [])
    additional_connections = Keyword.get(arg, :connections, [])
    rpc_enabled = Keyword.get(arg, :rpc_enabled, false)
    rpc_config = Keyword.get(arg, :rpc_config, nil)
    startup_consumers = Keyword.get(arg, :startup_consumers, [])

    connections = [] ++ additional_connections

    channel_registry = module.process_name("ChannelRegistry")
    pool_supervisor_name = module.process_name("PoolSupervisor")
    fluffle_supervisor_name = module.process_name("FluffleSupervisor")
    fluffle_registry_name = module.process_name("Fluffle.FluffleRegistry")

    # Store inital config for lookup later
    :ok =
      :persistent_term.put({WhiteRabbit, module}, %{
        init_keyword: arg,
        module: module,
        channel_registry: channel_registry,
        fluffle_supervisor_name: fluffle_supervisor_name,
        fluffle_registry_name: fluffle_registry_name
      })

    # Determine RPC config topology children
    rpc_children =
      if rpc_enabled && rpc_config !== nil,
        do: [configure_rpc_topology(rpc_config, parent_module: module)],
        else: []

    children =
      [
        # AMQP Channel Process Registry, channels are registered under connection_name atoms
        {Registry, [name: channel_registry, keys: :duplicate]},

        # WhiteRabbit connection super
        {PoolSupervisor, [module: module, name: pool_supervisor_name, connections: connections]},

        # WhiteRabbit consumer/producer super -> dynamic supers
        {Fluffle,
         [
           module: module,
           name: fluffle_supervisor_name,
           registry_name: fluffle_registry_name,
           startup_consumers: startup_consumers
         ]}
      ] ++ rpc_children ++ additional_children

    Logger.info("Starting the #{module} Hole")

    Supervisor.init(children, strategy: :rest_for_one)
  end

  def configure_rpc_topology(%WhiteRabbit.RPC.Config{} = config, opts) do
    parent_module = Keyword.get(opts, :parent_module, WhiteRabbit)
    reply_id = Core.uuid_tag()

    %RPC.Config{
      service_name: service_name,
      connection_name: connection_name
    } = config

    # Override with core RPC options
    service_consumer = %WhiteRabbit.Consumer{
      name: "#{service_name}.RPC.Receiver",
      exchange: "suzerain.rpcs.exchange",
      queue: "#{service_name}.rpcs",
      binding_keys: ["#{service_name}.rpcs"],
      owner_module: parent_module,
      connection_name: connection_name,
      queue_opts: [auto_delete: true],
      error_queue: false,
      processor: %WhiteRabbit.Processor.Config{
        module: RPC,
        function: :handle_rpc_message!
      }
    }

    # Override with core RPC options
    replies_consumer = %WhiteRabbit.Consumer{
      name: "#{service_name}.RPC.Replies",
      queue: "#{service_name}.rpcs.replies.#{reply_id}",
      binding_keys: ["#{reply_id}"],
      owner_module: parent_module,
      connection_name: connection_name,
      exchange: "amq.direct",
      exchange_type: :direct,
      queue_opts: [auto_delete: true, durable: false, exclusive: true],
      error_queue: false,
      processor: %WhiteRabbit.Processor.Config{
        module: RPC,
        function: :return_rpc_message!
      }
    }

    rpc_supervisor_name = parent_module.process_name("RPC.Supervisor")
    rpc_requests_registry = parent_module.process_name("RPCRequestRegistry")

    # Get init config map and add rpc_config, and process names
    merged_init_config =
      :persistent_term.get({WhiteRabbit, parent_module})
      |> Map.put(
        :rpc_config,
        %RPC.Config{
          service_consumer: service_consumer,
          replies_consumer: replies_consumer,
          service_name: service_name,
          reply_id: reply_id,
          connection_name: connection_name
        }
      )
      |> Map.put(:rpc_supervisor_name, rpc_supervisor_name)
      |> Map.put(:rpc_requests_registry, rpc_requests_registry)

    :persistent_term.put({WhiteRabbit, parent_module}, merged_init_config)

    rpc_children = [
      # RPC ETS Table (replaced with :persistent_term storage for now)
      # {WhiteRabbit.RPC.ProcessStore, [table_name: service_name, reply_id: reply_id, service_name: service_name]},

      # RPC Requests Registry
      {Registry, [name: rpc_requests_registry, keys: :unique]},

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
      id: rpc_supervisor_name,
      start: {Supervisor, :start_link, [rpc_children, [strategy: :rest_for_one]]},
      type: :supervisor
    }
  end
end
