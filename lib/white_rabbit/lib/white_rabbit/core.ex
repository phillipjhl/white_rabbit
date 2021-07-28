defmodule WhiteRabbit.Core do
  @moduledoc """
  Contains helper and util functions for the entire `WhiteRabbit` library.
  """

  alias WhiteRabbit.Consumer.State
  alias WhiteRabbit.Consumer
  alias WhiteRabbit

  alias AMQP.{Connection, Channel, Exchange, Queue, Basic}

  require Logger

  @doc """
  Setup of queues for the Consumer. Binds them to exhanges with all the routing_keys
  Uses `:exchange, :queue, :error_queue` from Genserver args for declaration.
  """
  def setup_queues(
        channel,
        %{
          exchange: exchange,
          queue: queue,
          error_queue: error_queue,
          binding_keys: binding_keys,
          queue_opts: queue_opts
        } = _opts
      ) do
    if error_queue do
      # Declare error queue set in Genserver options
      {:ok, _} = Queue.declare(channel, "#{queue}_errors", queue_opts)
    end

    Enum.each(binding_keys, &declare_queue(channel, queue, error_queue, exchange, queue_opts, &1))
  end

  @doc """
  Declare a queue with a dead-letter queue
  """
  @spec declare_queue(Channel.t(), String.t(), String.t(), Exchange.t(), Keyword.t(), String.t()) ::
          :ok
  def declare_queue(channel, queue, error_queue, exchange, queue_opts, binding_key) do
    # Messages that cannot be delivered to any consumer in the main queue will be routed to the error queue
    arguments =
      case error_queue do
        true ->
          [
            {"x-dead-letter-exchange", :longstr, ""},
            {"x-dead-letter-routing-key", :longstr, "#{queue}_errors"}
          ]

        _ ->
          []
      end

    queue_opts = queue_opts ++ [arguments: arguments]

    {:ok, _} = Queue.declare(channel, queue, queue_opts)

    # Bind queue to exchange for each routing key
    Queue.bind(channel, queue, exchange, routing_key: binding_key)
  end

  @doc """
   Setup an exchange with some default args.
  """
  @spec setup_exchange(Channel.t(), Exchange.t(), atom()) :: :ok
  def setup_exchange(
        channel,
        exchange,
        exchange_type
      ) do
    if String.length(exchange) > 0 do
      # Declare Exchange to use with Genserver Consumer
      Exchange.declare(channel, exchange, exchange_type, durable: true)
    end
  end

  @doc """
    Get the application's default channel. If not available, open another.

    You can monitor the returned channel for :DOWN events to be able to re-register as a consumer.
  """
  @spec get_channel(atom(), atom()) :: {:ok, Channel.t()}
  def get_channel(channel_name, connection_name) do
    case AMQP.Application.get_channel(channel_name) do
      {:ok, chan} ->
        {:ok, chan}

      {:error, error} ->
        Logger.error("#{inspect(error)}")
        # Retrying
        :timer.sleep(5000)

        get_channel(channel_name, connection_name)
    end
  rescue
    error ->
      Logger.error("#{inspect(error)}")

      {:ok, conn} = AMQP.Application.get_connection(:white_rabbit)
      Channel.open(conn)
  end

  @doc """
  Get a random channel from the pool to use.

  Returns `{:ok, AMQP.Channel.t()}`
  """
  @spec get_channel_from_pool(connection_name :: atom(), registry :: atom()) ::
          {:ok, AMQP.Channel.t()} | {:error, any()}
  def get_channel_from_pool(connection_name, registry)
      when is_atom(connection_name) and is_atom(registry) do
    channels = Registry.lookup(registry, connection_name)

    if Enum.empty?(channels) do
      {:error, :no_channels_registered}
    else
      # return random channel from the pool for now, hopefully law of averages holds up
      # {pid, channel} = Enum.random(channels)
      {:ok, Enum.random(channels)}
    end
  end

  @spec test_publish(integer(), String.t(), String.t(), map(), Keyword.t()) :: [atom()]
  def test_publish(
        number \\ 100,
        exchange \\ "json_test_exchange",
        routing_key \\ "test_json",
        payload \\ %{hello: "world"},
        options \\ []
      ) do
    # {:ok, {_pid, channel}} = get_channel_from_pool(:whiterabbit_default_connection)
    # exchange = "json_test_exchange"
    # routing_key = "test_json"
    payload = Jason.encode!(payload)

    all_options =
      [
        content_type: "application/json"
      ] ++ options

    for _i <- 1..number do
      WhiteRabbit.Producer.publish(:aggie_connection, exchange, routing_key, payload, all_options)
    end
  end

  @doc """
  Consume function that actually processes the message.any()

  TO DO: Probably need to have the actual 'processor' functions in seperate spawned workers to keep them out
  of the Consumer Genserver process. The spawned workers can then send acks or rejects.

  """
  defp test_consume(channel, payload, %{delivery_tag: tag, redelivered: redelivered} = meta) do
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

  @spec uuid_tag(integer) :: binary
  def uuid_tag(bytes_count \\ 8) do
    bytes_count
    |> :crypto.strong_rand_bytes()
    |> Base.url_encode64(padding: false)
  end

  @doc """
  Get backoff delay from linked agent.
  """
  @spec get_backoff(Agent.agent()) :: non_neg_integer()
  def get_backoff(agent_pid) do
    Agent.get_and_update(agent_pid, fn c -> {c, c * 2} end)
  end
end
