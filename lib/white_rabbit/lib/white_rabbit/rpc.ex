defmodule WhiteRabbit.RPC do
  @moduledoc """
  RPC module that handles decoding, encoding, and processing of RPC calls.

  #### Testing
  `iex> WhiteRabbit.RPC.call("aggie", {IO, :puts, ["hello there"]})`
  """
  require Logger
  require Jason

  alias WhiteRabbit.{Producer, Core}
  alias AMQP.{Basic}

  @typedoc """
  Service that the call will be sent to.

  Ex: "aggie"
  """
  @type service_rpc :: String.t()

  @spec call(service_rpc, {module, atom(), []}) :: {:ok, any()} | {:error, any()}
  def call(service, mfa) do
    # get caller_id of running reply consumer
    {:ok, caller_id} = WhiteRabbit.RPC.ProcessStore.fetch_id(service)

    Logger.debug("Retreived reply_id: #{inspect(caller_id)}")

    call(caller_id, service, mfa)
  end

  @spec call(String.t(), service_rpc, {module, atom(), []}) :: {:ok, any()} | {:error, any()}
  defp call(caller_id, service, mfa) do
    {module, func, args} = mfa
    payload = Jason.encode!(%{caller_id: caller_id, module: module, function: func, args: args})

    caller_pid = self()

    Logger.debug("Caller pid: #{inspect(caller_pid)}")

    :ok =
      Producer.publish(
        :whiterabbit_rpc_conn,
        "suzerain.rpcs.exchange",
        "#{service}.rpcs",
        payload,
        reply_to: caller_id
      )

    Registry.register(RPCRequestRegistry, caller_id, caller_id)
  end

  def return_rpc_message!(channel, message, metadata) do
    Logger.debug("Handling Returned RPC msg: #{inspect(message)} #{inspect(metadata)}")

    decoded_msg = message |> Jason.decode!()
    Logger.debug("Decoded Message: #{inspect(decoded_msg)}")

    # get caller process id
    case Registry.lookup(RPCRequestRegistry, metadata.routing_key) do
      [{pid, value}] ->
        Logger.debug("Caller process matched: pid: #{inspect(pid)}, value: #{inspect(value)}")
        :ok = Basic.ack(channel, metadata.delivery_tag)
        # send message (returned result) to process id
        send(pid, decoded_msg)

      [] ->
        Basic.reject(channel, metadata.delivery_tag, requeue: false)
        {:error, :caller_not_found}
    end
  end

  def handle_rpc_message!(channel, message, metadata) do
    Logger.debug("Receiving RPC msg: #{inspect(message)} #{inspect(metadata)}")

    response =
      message
      |> decode_rpc_message!()
      |> process_rpc_message!()
      |> encode_rpc_message!()

    Basic.ack(channel, metadata.delivery_tag)

    Logger.debug("Responding to RPC with: #{inspect(response)}, to: #{metadata.reply_to}")

    WhiteRabbit.Producer.publish(
      :whiterabbit_rpc_conn,
      "amq.direct",
      metadata.reply_to,
      response,
      []
    )
  end

  defp process_rpc_message!(%WhiteRabbit.RPC.Message{} = message) do
    %WhiteRabbit.RPC.Message{
      module: module,
      function: function,
      args: args,
      caller_id: caller_id
    } = message

    Logger.debug("Processing RPC msg: #{inspect(message)}")

    # apply(module, function, args)

    :ok
  end

  defp process_rpc_message!(message) do
    # {module, function, args} = message

    Logger.debug("Processing RPC msg: #{inspect(message)}")

    # apply(module, function, args)

    :ok
  end

  defp decode_rpc_message!(message) do
    message
    |> Jason.decode!()
    |> WhiteRabbit.RPC.Message.convert!()
  end

  defp encode_rpc_message!(data) do
    encode_map = %{
      response: data
    }

    encode_map
    |> Jason.encode!()
  end

  def test_receive do
    call("aggie", {IO, :puts, ["hello world"]})

    receive do
      msg -> msg
    end
  end
end
