defmodule WhiteRabbit.Producer do
  @moduledoc """
  WhiteRabbit.Producer behaviour module that publishes messages using its callbacks.

  ## Using The Module
  ### Using the `use` macro
  ```
  defmodule Aggie.Producer.Json do
    use WhiteRabbit.Producer

    def test_publish do
      data = %{hello: "there", general: :kenobi}

      payload = Jason.encode!(data)

      # Use default publish/5 function
      publish(:aggie_connection, "json_test_exchange", "test_json", payload,
        content_type: "aplication/json",
        persistent: true
      )
    end

  end
  ```

  ### Overide default callback
  ```
  # or override it with custom callback
  def publish(conn, exchange, queue, payload, options) do
    # custom logic

    # Send AMQP.Basic.publish/5 message

    # more custom logic
  end
  ```

  ### Or just use the publish/5 function directly

  Default automatically emits :telemetry events with the names:

  -  `[:white_rabbit, :publish, :start]`

  -  `[:white_rabbit, :publish, :stop]`

  ```
  iex> WhiteRabbit.Producer.publish(:aggie_conn, "test_exchange", "test_route", "hello there", persistent: true)
  :ok
  ```
  """

  require Logger
  alias AMQP.Basic
  alias WhiteRabbit.Core

  defmacro __using__(_opts) do
    quote do
      @behaviour WhiteRabbit.Producer

      def publish(conn_pool, exchange, routing_key, message, options) do
        WhiteRabbit.Producer.publish(conn_pool, exchange, routing_key, message, options)
      end

      defoverridable publish: 5
    end
  end

  @typedoc """
  Return on publish of message
  """
  @type on_publish :: :ok

  @type channel :: AMQP.Channel.t()

  @typedoc """
  ### Publish Options:
  :mandatory - If set, returns an error if the broker can't route the message to a queue (default false)

  :immediate - If set, returns an error if the broker can't deliver the message to a consumer immediately (default false)

  :content_type - MIME Content type

  :content_encoding - MIME Content encoding

  :headers - Message headers of type t:AMQP.arguments/0. Can be used with headers Exchanges

  :persistent - If set, uses persistent delivery mode. Messages marked as persistent that are delivered to durable queues will be logged to disk

  :correlation_id - application correlation identifier

  :priority - message priority, ranging from 0 to 9

  :reply_to - name of the reply queue

  :expiration - how long the message is valid (in milliseconds)

  :message_id - message identifier

  :type - message type as a string

  :user_id - creating user ID. RabbitMQ will validate this against the active connection user

  :app_id - publishing application ID
  """
  @type publish_options :: Keyword.t()

  # Callbacks

  @callback publish(
              conn_pool :: atom(),
              exchange :: String.t(),
              routing_key :: String.t(),
              message :: any(),
              options :: publish_options
            ) :: on_publish

  # @optional_callbacks [publish: 5]

  @doc """
  Tries to publish message with a channel from a pool if a channel is found.

  Returns `:ok` if successful

  ### Attaches some :telemetry events as well:

  -  `[:white_rabbit, :publish, :start]`
    - measurements:
      - time: :naive unix timestamp
      - count: 1

  -  `[:white_rabbit, :publish, :stop]`
    - measurements:
      - duration: :naive unix timestamp
      - count: 1

  - metadata: %{
      conn_pool: conn_pool,
      exchange: exchange,
      routing_key: routing_key,
      module: __MODULE__
    }
  """
  @spec publish(
          conn_pool :: atom(),
          exchange :: String.t(),
          routing_key :: String.t(),
          message :: any(),
          options :: publish_options
        ) :: on_publish
  def publish(conn_pool, exchange, routing_key, message, options) do
    # event metadata
    metadata = %{
      conn_pool: conn_pool,
      exchange: exchange,
      routing_key: routing_key,
      module: __MODULE__
    }

    start = :os.system_time()

    :telemetry.execute(
      [:white_rabbit, :publish, :start],
      %{time: :os.system_time(), count: 1},
      metadata
    )

    channel =
      case Core.get_channel_from_pool(conn_pool) do
        {:ok, {_pid, channel}} ->
          channel

        {:error, reason} ->
          Logger.error("#{reason}")
          nil
      end

    if channel do
      all_options =
        [
          timestamp: start
        ] ++ options

      result = Basic.publish(channel, exchange, routing_key, message, all_options)

      stop = :os.system_time()

      :telemetry.execute(
        [:white_rabbit, :publish, :stop],
        %{
          duration: stop - start,
          count: 1
        },
        metadata
      )

      # Return result of Basic.publish()
      result
    end
  end

  defoverridable publish: 5
end
