defmodule WhiteRabbit.Consumer do
  @moduledoc """
  Consumer GenServer that will handle connecting to a channel using a configured connection and then declare an
  exchange and queue to handle messages from a RabbitMQ broker server.

  This module should only be concerned about establishing channels and registering itself as a consumer.

  Actual processing of incoming messages are handled externally through configerd processors. See `WhiteRabbit.Processor` behavior.

  ## Start under a supervisor with child_spec:

  ```
  children = [
    %{
      id: :WhiteRabbitConsumer,
      start:
        {WhiteRabbit.Consumer, :start_link,
         [
           %WhiteRabbit.Consumer{
             name: :WhiteRabbitConsumer,
             exchange: "WhiteRabbitConsumer_exchange",
             queue: "WhiteRabbitConsumer_queue"
           }
         ]}
    },
  ]

  Supervisor.init(children, strategy: :one_for_one)
  ```

  ## Starting under the Fluffle dynamic superviser

  ```
  DynamicSupervisor.start_child(
    AppOne.WhiteRabbit.Fluffle.DynamicSupervisor.Consumer,
    {WhiteRabbit.Consumer, %WhiteRabbit.Consumer{
        owner_module: AppOne.WhiteRabbit,
        connection_name: :appone_connection,
        name: "AppOne.JsonConsumer",
        exchange: "json_test_exchange",
        queue: "json_test_queue",
        processor: %WhiteRabbit.Processor.Config{module: AppOne.TestJsonProcessor}
      }
    }
  )
  ```

  #### To Do:
  Maybe even include a handle_info function that can dynamically spawn more workers on demand by a specific message payload.

  """

  use GenServer, restart: :transient
  import WhiteRabbit.Core

  alias AMQP.{Basic}

  alias WhiteRabbit.{Consumer}

  require Logger

  @enforce_keys [:name, :queue, :processor, :connection_name]
  defstruct name: __MODULE__,
            owner_module: WhiteRabbit,
            exchange: "",
            queue: "",
            queue_opts: [durable: true],
            error_queue: true,
            channel_name: :default_consumer_channel,
            connection_name: nil,
            exchange_type: :topic,
            binding_keys: ["#"],
            processor: nil,
            prefetch_count: 100,
            uuid_name: "",
            channel_registry: nil

  @type t :: %__MODULE__{
          name: __MODULE__.t(),
          owner_module: module(),
          exchange: String.t(),
          queue: String.t(),
          queue_opts: Keyword.t(),
          error_queue: boolean(),
          channel_name: String.t(),
          connection_name: String.t(),
          exchange_type: atom(),
          binding_keys: [String.t()],
          processor: WhiteRabbit.Processor.Config.t(),
          prefetch_count: integer(),
          uuid_name: String.t(),
          channel_registry: term()
        }

  @doc """
  Start a WhiteRabbit Consumer Genserver.
  """
  def start_link(%Consumer{name: name} = args) when is_atom(name) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def start_link(%Consumer{name: name, owner_module: owner_module} = args) do
    init_config = :persistent_term.get({WhiteRabbit, owner_module})

    %{fluffle_registry_name: fluffle_registry_name, channel_registry: channel_registry} =
      init_config

    uuid_name = "#{name}-#{uuid_tag(8)}"
    Logger.debug(uuid_name)
    # add additional overridden fields
    args = Map.put(args, :uuid_name, uuid_name) |> Map.put(:channel_registry, channel_registry)
    Logger.debug(inspect(args))
    GenServer.start_link(__MODULE__, args, name: register_name(uuid_name, fluffle_registry_name))
  end

  def register_name(name, registry_name \\ WhiteRabbit.Fluffle.FluffleRegistry) do
    {:via, Registry, {registry_name, name}}
  end

  @impl true
  def init(
        %Consumer{
          connection_name: connection_name
        } = args
      ) do
    # Get Channel and Monitor
    case get_channel_from_pool(connection_name, args.channel_registry) do
      {:ok, {_pid, _channel} = channel} ->
        {:ok, state} = init_consumer(args, channel)
        {:ok, state}

      {:error, error} ->
        # Start backoff agent
        {:ok, agent_pid} = Agent.start_link(fn -> 1 end)

        Logger.error(
          "Error getting channel from pool: #{error}. Try restarting the child if a connection is made."
        )

        {:ok,
         %Consumer.State{
           consumer_init_args: args,
           backoff_agent_pid: agent_pid
         }, {:continue, error}}
    end
  end

  # Confirmation sent by the broker after registering this process as a consumer
  @impl true
  def handle_info(
        {:basic_consume_ok, %{consumer_tag: consumer_tag}},
        %Consumer.State{state: %{channel: _channel, queue: queue}} = state
      ) do
    Logger.info("#{__MODULE__} registered #{inspect(consumer_tag)} to #{queue}")
    {:noreply, state}
  end

  # Sent by the broker when the consumer is unexpectedly cancelled (such as after a queue deletion)
  @impl true
  def handle_info(
        {:basic_cancel, %{consumer_tag: _consumer_tag}},
        %Consumer.State{state: %{channel: _channel}} = state
      ) do
    {:stop, :abnormal, state}
  end

  # Confirmation sent by the broker to the consumer process after a Basic.cancel
  @impl true
  def handle_info(
        {:basic_cancel_ok, %{consumer_tag: _consumer_tag}},
        %Consumer.State{state: %{channel: _channel}} = state
      ) do
    {:noreply, state}
  end

  @impl true
  def handle_info(
        {:basic_deliver, payload, meta},
        %Consumer.State{state: %{channel: channel, processor: processor}} = state
      ) do
    Logger.debug("Received Message: #{inspect(self())} | #{inspect(payload)} | #{inspect(meta)}")

    # To Do: Should this be spawned tasks linked to this process to prevent blocking? Maybe.
    # But can also just configure a certain number of consumers on the same queue to provide concurrency as well. (Current Way)
    %{module: processor_module, function: processor_function} = processor

    # If there is a given function, then apply that mfa
    Logger.debug(inspect(processor))

    if processor_function !== nil do
      apply(processor_module, processor_function, [channel, payload, meta])
    else
      case processor_module.consume_payload(payload, meta) do
        {:ok, tag} ->
          :telemetry.execute(
            [:white_rabbit, :ack],
            %{count: 1, duration: :os.system_time() - meta.timestamp},
            meta
          )

          Basic.ack(channel, tag)

        {:error, {tag, opts}} ->
          :telemetry.execute(
            [:white_rabbit, :reject],
            %{count: 1, duration: :os.system_time() - meta.timestamp},
            meta
          )

          Basic.reject(channel, tag, opts)
      end
    end

    {:noreply, state}
  end

  @doc """
   Handle incoming channel_monitor messages to allow for recovering of down channels
  """
  def handle_info(
        :channel_monitor,
        %Consumer.State{consumer_init_args: consumer_init_args} = state
      ) do
    case channel_monitor(consumer_init_args) do
      {:ok, chan} ->
        {:noreply, Map.put(state.state, :channel, chan)}

      _ ->
        {:noreply, state}
    end
  end

  # Handle monitored channel to allow for restarts of Consumer so it can re-register the restarted GenServer with new open channel.
  @impl true
  def handle_info(
        {:DOWN, _, :process, _pid, _reason},
        %Consumer.State{} = _state
      ) do
    {:stop, :channel_died}
  end

  # Handle a :graceful_stop message to allow for normal stop of Consumer. Useful for killing excessive Consumer that were started
  # with the `WhiteRabbit.Fluffle` DynamicSupervisor
  @impl true
  def handle_info(:graceful_stop, %Consumer.State{} = state) do
    Logger.info("Stopping Consumer Genserver normally.")
    {:stop, :normal, state}
  end

  @impl true
  # Catch all others
  def handle_info(_, state) do
    {:noreply, state}
  end

  @impl true
  def handle_continue(:no_channels_registered, %Consumer.State{} = state) do
    %{consumer_init_args: consumer_init_args} = state

    backoff_exp = get_backoff(state.backoff_agent_pid)
    backoff_delay = 6000 + 1000 * backoff_exp

    Logger.info(
      "Retrying to init #{consumer_init_args.uuid_name} after #{backoff_delay / 1000} seconds."
    )

    :timer.sleep(backoff_delay)

    with {:ok, channel} <-
           get_channel_from_pool(
             consumer_init_args.connection_name,
             consumer_init_args.channel_registry
           ),
         {:ok, new_state} <- init_consumer(consumer_init_args, channel) do
      {:noreply, new_state, state}
    else
      {:error, reason} -> {:noreply, state, {:continue, reason}}
    end
  end

  # Catch remaining continue commands
  @impl true
  def handle_continue(_continue, state) do
    {:noreply, state}
  end

  @doc """
  Register process as consumer.

  Returns {:ok, %{channel: active_channel, consumer_tag: consumer_tag}} if succesful.

  Monitors the active AMQP Channel process pid to allow parent process to handle incoming :DOWN messages.

  Sets the prefetch_count for the given connection as well.
  """
  def register_consumer(pid, active_channel, %Consumer{} = args) do
    %Consumer{
      queue: queue,
      prefetch_count: prefetch_count,
      name: _name,
      uuid_name: uuid_name
    } = args

    # Monitor Channel Process to allow for recovery
    Process.monitor(pid)

    # Limit unacknowledged messages to given prefetch_count
    Basic.qos(active_channel, prefetch_count: prefetch_count)

    # Register the GenServer process as a consumer to the server
    {:ok, consumer_tag} = Basic.consume(active_channel, queue, nil, consumer_tag: "#{uuid_name}")

    {:ok, %{channel: active_channel, consumer_tag: consumer_tag}}
  end

  defp channel_monitor(%Consumer{} = args) do
    %Consumer{
      channel_name: channel_name
    } = args

    case get_channel(channel_name) do
      {:ok, %AMQP.Channel{} = channel} ->
        register_consumer(channel.pid, channel, args)

      {:error, _reason} ->
        Process.send_after(self(), :channel_monitor, 5000)
        {:error, :retrying}
    end
  end

  @spec init_consumer(args :: map(), channel :: {pid(), any()}) :: {:ok, map()}
  defp init_consumer(%Consumer{} = args, channel) do
    %Consumer{
      queue: queue,
      processor: processor
    } = args

    {pid, active_channel} = channel

    # Declare exchanges
    setup_exchange(active_channel, args.exchange, args.exchange_type)

    # Declare queues
    setup_queues(active_channel, args)

    # Register consumer to configured queue.
    {:ok, %{channel: active_channel, consumer_tag: consumer_tag}} =
      register_consumer(pid, active_channel, args)

    # Init state
    state = %Consumer.State{
      consumer_init_args: args,
      state: %{
        channel: active_channel,
        queue: queue,
        consumer_tag: consumer_tag,
        processor: processor
      }
    }

    {:ok, state}
  end

  @doc """
  Start a number of Consumer with the given config.

  Pass a `WhiteRabbit.Consumer{}` to start it under a DynamicSupervisor.

  Optionally pass an integer as the second argument to start any number of Consumers with the same config.
  """
  @spec start_dynamic_consumers(
          config :: Consumer.t(),
          concurrency :: integer(),
          owner_module :: module()
        ) :: [
          tuple()
        ]
  def start_dynamic_consumers(%Consumer{} = config, concurrency, owner_module)
      when is_integer(concurrency) and is_map(config) do
    for _i <- 1..concurrency do
      supervisor =
        "#{owner_module}.Fluffle.DynamicSupervisor.Consumer" |> String.to_existing_atom()

      DynamicSupervisor.start_child(
        supervisor,
        {WhiteRabbit.Consumer, config}
      )
    end
  end
end
