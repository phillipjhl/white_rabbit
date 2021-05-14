defmodule WhiteRabbit.Core do
  @moduledoc """
  Contains helper functions.
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
          binding_keys: binding_keys
        } = _opts
      ) do
    if error_queue do
      # Declare error queue set in Genserver options
      {:ok, _} = Queue.declare(channel, "#{queue}_errors", durable: true)
    end

    Enum.each(binding_keys, &declare_queue(channel, queue, error_queue, exchange, &1))
  end

  @doc """
  Declare a queue with a dead-letter queue
  """
  @spec declare_queue(Channel.t(), String.t(), String.t(), Exchange.t(), String.t()) :: :ok
  def declare_queue(channel, queue, error_queue, exchange, binding_key) do
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

    {:ok, _} =
      Queue.declare(channel, queue,
        durable: true,
        arguments: arguments
      )

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
    # Declare Exchange to use with Genserver Consumer
    Exchange.declare(channel, exchange, exchange_type, durable: true)
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
end
