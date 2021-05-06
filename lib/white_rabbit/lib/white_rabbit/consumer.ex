defmodule WhiteRabbit.Consumer do
  @moduledoc """
  AMQP Consumer Genserver that will handle connecting to a channel using a configured connection and then declare an
  exchange and queue to handle messages from a RabbitMQ broker server.

  This module should only be concerned about establishing channels and registering itself as a consumer.

  Maybe even include a handle_info function that can dynamically spawn more workers on demand by a specific message payload.

  Actual processing of incoming messages should be handled externally.

  Start under a supervisor:

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
  """

  use GenServer
  use WhiteRabbit.Core

  require Logger

  @enforce_keys [:name, :queue]
  defstruct name: __MODULE__,
            exchange: "",
            queue: "",
            error_queue: true,
            channel_name: :white_rabbit_consumer,
            connection_name: :white_rabbit,
            exchange_type: :topic,
            binding_keys: ["#"]

  @type t :: %__MODULE__{
          name: __MODULE__.t(),
          exchange: String.t(),
          queue: String.t(),
          error_queue: boolean(),
          channel_name: String.t(),
          connection_name: Sting.t(),
          exchange_type: atom(),
          binding_keys: [String.t()]
        }

  @doc """
  Start a WhiteRabbit Consumer Genserver.
  """
  @spec start_link(Keyword.t()) :: GenServer.start_link()
  def start_link(%Consumer{name: name} = args) do
    GenServer.start_link(__MODULE__, args, name: name)
  end

  @impl true
  def init(
        %Consumer{channel_name: channel_name, connection_name: connection_name, queue: queue} =
          args
      ) do
    # Get Channel and Monitor
    {:ok, channel} = get_channel(channel_name, connection_name)

    # Declare exchanges
    setup_exchange(channel, args.exchange, args.exchange_type)

    # Declare queues
    setup_queues(channel, args)

    {:ok, %{channel: channel, consumer_tag: consumer_tag}} = channel_monitor(args)

    # Init state
    state = %Consumer.State{
      consumer_init_args: args,
      state: %{channel: channel, queue: queue, consumer_tag: consumer_tag}
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
        %Consumer.State{state: %{channel: channel}} = state
      ) do
    # We might want to run payload consumption in separate Tasks in production
    consume(channel, payload, meta)

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
    send(self(), :channel_monitor)
    {:noreply, Map.put(state.state, :channel, nil)}
  end

  @impl true
  # Catch all others
  def handle_info(_, state) do
    {:noreply, state}
  end

  @doc """
  Consume function that actually processes the message.any()

  TO DO: Probably need to have the actual 'processor' functions in seperate spawned workers to keep them out
  of the Consumer Genserver process. The spawned workers can then send acks or rejects.

  """
  defp consume(channel, payload, %{delivery_tag: tag, redelivered: redelivered} = meta) do
    Logger.debug(
      "Received Message: #{inspect(self())} | #{inspect(tag)} | #{inspect(payload)} | #{
        inspect(meta)
      }"
    )

    %{content_type: content_type} = meta

    case content_type do
      "application/json" ->
        {:ok, _json} = Jason.decode(payload)

        # If decoded, send ack to server
        Basic.ack(channel, tag)

      _ ->
        Logger.warn(
          "Payload #{inspect(tag)} did not have correct content_type property set. Not requeing."
        )

        :ok = Basic.reject(channel, tag, requeue: false)
    end
  rescue
    # Requeue unless it's a redelivered message.
    # This means we will retry consuming a message once in case of exception
    # before we give up and have it moved to the error queue

    exception ->
      # To Do: Further iterations should be able to discern if the error was internal or not. If a failure is caused
      # an internal/external service being down for instance, there should be a dedicated queue to allow for re-routing and re-processing if needed.
      Logger.warn("Error consuming message: #{tag} #{inspect(exception)}")
      :ok = Basic.reject(channel, tag, requeue: not redelivered)
  end

  defp channel_monitor(
         %Consumer{connection_name: connection_name, channel_name: channel_name, queue: queue} =
           _args
       ) do
    case get_channel(channel_name, connection_name) do
      {:ok, channel} ->
        # Monitor Channel Process to allow for recovery
        Process.monitor(channel.pid)

        # Limit unacknowledged messages to 10
        Basic.qos(channel, prefetch_count: 10)

        # Register the GenServer process as a consumer to the server
        {:ok, consumer_tag} = Basic.consume(channel, queue)

        {:ok, %{channel: channel, consumer_tag: consumer_tag}}

      _ ->
        Process.send_after(self(), :channel_monitor, 5000)
        {:error, :retrying}
    end
  end
end
