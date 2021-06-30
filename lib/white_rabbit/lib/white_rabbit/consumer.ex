defmodule WhiteRabbit.Consumer do
  @moduledoc """
  AMQP Consumer Genserver that will handle connecting to a channel using a configured connection and then declare an
  exchange and queue to handle messages from a RabbitMQ broker server.

  This module should only be concerned about establishing channels and registering itself as a consumer.

  Actual processing of incoming messages are handled externally through configerd processors. See `WhiteRabbit.Processor` behavior.

  ## Start under a supervisor:

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
    WhiteRabbit.Fluffle.DynamicSupervisor.Consumer,
    {WhiteRabbit.Consumer, %WhiteRabbit.Consumer{
      connection_name: :aggie_connection,
      name: "Aggie.JsonConsumer",
      exchange: "json_test_exchange",
      queue: "json_test_queue",
      processor: %WhiteRabbit.Processor.Config{module: Aggie.TestJsonProcessor},
      prefetch_count: 50
      }
    }
  )
  ```

  for i <- 1..100 do
  IO.puts(i)
  AMQP.Basic.publish(%AMQP.Channel{conn: %AMQP.Connection{pid: #PID<0.1325.0>}, custom_consumer: {AMQP.SelectiveConsumer, #PID<0.1339.0>}, pid: #PID<0.1343.0>}, "json_test_exchange", "", Jason.encode!(%{test: "hello"}))
  end

  #### To Do:
  Maybe even include a handle_info function that can dynamically spawn more workers on demand by a specific message payload.

  """

  use GenServer, restart: :transient
  import WhiteRabbit.Core

  alias AMQP.{Connection, Channel, Exchange, Queue, Basic}

  alias WhiteRabbit.{Consumer}

  require Logger

  @enforce_keys [:name, :queue, :processor]
  defstruct name: __MODULE__,
            exchange: "",
            queue: "",
            queue_opts: [durable: true],
            error_queue: true,
            channel_name: :default_consumer_channel,
            connection_name: :whiterabbit_default_connection,
            exchange_type: :topic,
            binding_keys: ["#"],
            processor: nil,
            prefetch_count: 100,
            uuid_name: ""

  @type t :: %__MODULE__{
          name: __MODULE__.t(),
          exchange: String.t(),
          queue: String.t(),
          queue_opts: Keyword.t(),
          error_queue: boolean(),
          channel_name: String.t(),
          connection_name: Sting.t(),
          exchange_type: atom(),
          binding_keys: [String.t()],
          processor: WhiteRabbit.Processor.Config.t(),
          prefetch_count: integer(),
          uuid_name: String.t()
        }

  @doc """
  Start a WhiteRabbit Consumer Genserver.
  """
  def start_link(%Consumer{name: name} = args) when is_atom(name) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  def start_link(%Consumer{name: name} = args) do
    uuid_name = "#{name}-#{uuid_tag(8)}"
    Logger.debug(uuid_name)
    args = Map.put(args, :uuid_name, uuid_name)
    Logger.debug(inspect(args))
    GenServer.start_link(__MODULE__, args, name: register_name(uuid_name))
  end

  def register_name(name) do
    {:via, Registry, {FluffleRegistry, name}}
  end

  @impl true
  def init(
        %Consumer{
          connection_name: connection_name,
          queue: queue,
          processor: processor
        } = args
      ) do
    # Get Channel and Monitor
    {:ok, {pid, channel}} = get_channel_from_pool(connection_name)

    # Declare exchanges
    setup_exchange(channel, args.exchange, args.exchange_type)

    # Declare queues
    setup_queues(channel, args)

    {:ok, %{channel: channel, consumer_tag: consumer_tag}} = register_consumer(pid, channel, args)

    # Init state
    state = %Consumer.State{
      consumer_init_args: args,
      state: %{
        channel: channel,
        queue: queue,
        consumer_tag: consumer_tag,
        processor: processor
      }
    }

    {:ok, state}
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
    {:stop, :normal, state}
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
    # But can also just configure a certain number of consumers on the same queue to provide concurrency as well.
    %{module: processor_module, function: processor_function} = processor

    if processor_function do
      apply(processor_module, processor_function, [channel, payload, meta])
    else
      case processor.consume_payload(payload, meta) do
        {:ok, tag} -> Basic.ack(channel, tag)
        {:error, {tag, opts}} -> Basic.reject(channel, tag, opts)
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

  def handle_info(
        {:DOWN, _, :process, pid, reason},
        %Consumer.State{state: %{channel: %{pid: pid}}} = state
      ) do
    {:stop, :channel_died}
  end

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

  defp register_consumer(pid, active_channel, %Consumer{} = args) do
    %Consumer{
      queue: queue,
      prefetch_count: prefetch_count,
      name: name,
      uuid_name: uuid_name
    } = args

    # Monitor Channel Process to allow for recovery
    Process.monitor(pid)

    # Limit unacknowledged messages to given prefetch_count
    Basic.qos(active_channel, prefetch_count: prefetch_count)

    # Register the GenServer process as a consumer to the server
    {:ok, consumer_tag} =
      Basic.consume(active_channel, queue, nil, consumer_tag: "ctag-#{uuid_name}")

    {:ok, %{channel: active_channel, consumer_tag: consumer_tag}}
  end

  defp channel_monitor(%Consumer{} = args) do
    %Consumer{
      connection_name: connection_name,
      channel_name: channel_name,
      queue: queue,
      prefetch_count: prefetch_count
    } = args

    case get_channel(channel_name, connection_name) do
      {:ok, channel} ->
        # Monitor Channel Process to allow for recovery
        Process.monitor(channel.pid)

        # Limit unacknowledged messages to given prefetch_count
        Basic.qos(channel, prefetch_count: prefetch_count)

        # Register the GenServer process as a consumer to the server
        {:ok, consumer_tag} = Basic.consume(channel, queue)

        {:ok, %{channel: channel, consumer_tag: consumer_tag}}

      _ ->
        Process.send_after(self(), :channel_monitor, 5000)
        {:error, :retrying}
    end
  end

  def test_start_dynamic_consumers(config, concurrency)
      when is_integer(concurrency) and is_map(config) do
    %WhiteRabbit.Consumer{
      connection_name: connection_name,
      name: name,
      exchange: exchange,
      queue: queue,
      processor: processor
    } = config

    for i <- 1..concurrency do
      DynamicSupervisor.start_child(
        WhiteRabbit.Fluffle.DynamicSupervisor.Consumer,
        {WhiteRabbit.Consumer,
         %WhiteRabbit.Consumer{
           connection_name: connection_name,
           name: "#{name}:#{i}",
           exchange: exchange,
           queue: queue,
           processor: processor
         }}
      )
    end
  end
end
