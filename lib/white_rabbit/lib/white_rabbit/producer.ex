defmodule WhiteRabbit.Producer do
  @moduledoc """
  WhiteRabbit.Producer behaviour that publishes messages using its callbacks.

  ```
  defmodule Aggie.Producer.Json do
    use WhiteRabbit.Producer

  end
  ```

  ```
  iex> payload = Jason.encode!(%{hello: "there"})
  iex> Aggie.Producer.Json.publish(:aggie_connection, "json_test_exchange", "test_json", payload, [content_type: "aplication/json"])
  ```
  """

  require Logger
  alias AMQP.Basic

  import WhiteRabbit.Core

  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts, module: __CALLER__.module] do
      require Logger
      alias AMQP.Basic

      import WhiteRabbit.Core

      @type channel :: AMQP.Channel.t()

      @callback handle_before_publish() :: {:ok, any()} | {:error, any()}
      @callback handle_after_publish() :: {:ok, any()} | {:error, any()}

      def publish(conn_pool, exchange, routing_key, message, options),
        do: WhiteRabbit.Producer.publish(conn_pool, exchange, routing_key, message, options)

      defoverridable publish: 5
    end
  end

  @doc """
  Tries to publish message with a channel from a pool if a channel is found.

  Attaches some :telemetry events as well.
  """
  @spec publish(
          conn_pool :: atom(),
          exchange :: String.t(),
          routing_key :: String.t(),
          message :: any(),
          options :: Keyword.t()
        ) :: :ok
  def publish(conn_pool, exchange, routing_key, message, options) do
    # event metadata
    metadata = %{
      conn_pool: conn_pool,
      exchange: exchange,
      routing_key: routing_key,
      module: __MODULE__
    }

    start = :os.system_time(:millisecond)

    :telemetry.execute(
      [:white_rabbit, :publish, :start],
      %{time: :os.system_time(:millisecond), count: 1},
      metadata
    )

    channel =
      case get_channel_from_pool(conn_pool) do
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

      stop = :os.system_time(:millisecond)

      :telemetry.execute(
        [:white_rabbit, :publish, :stop],
        %{
          duration: stop - start,
          count: 1
        },
        %{
          conn_pool: conn_pool,
          exchange: exchange,
          routing_key: routing_key,
          module: __MODULE__
        }
      )

      # Return result of Basic.publish()
      result
    end
  end
end
