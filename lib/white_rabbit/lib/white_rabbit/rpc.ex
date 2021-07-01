defmodule WhiteRabbit.RPC do
  @moduledoc """
  RPC module that handles decoding, encoding, and processing of RPC calls.

  #### Testing
  `iex> WhiteRabbit.RPC.call("aggie", {Aggie.Utils, :get_versions, []})`
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

  @spec call(service_rpc, {module, atom(), []}, timeout :: integer()) ::
          {:ok, any()} | {:error, any()}
  def call(service, mfa, timeout \\ 5000) do
    # get caller_id of running reply consumer
    {:ok, caller_id} = WhiteRabbit.RPC.ProcessStore.fetch_id(service)

    Logger.debug("#{service} client reply_id: #{inspect(caller_id)}")

    # Start task, return awaited result
    task = Task.async(fn -> call(caller_id, service, mfa, timeout) end)
    Task.await(task, timeout)
  end

  @spec call(String.t(), service_rpc, {module, atom(), []}, timeout :: integer()) ::
          {:ok, any()} | {:error, any()}
  defp call(caller_id, service, mfa, timeout) do
    {module, func, args} = mfa

    payload = Jason.encode!(%{caller_id: caller_id, module: module, function: func, args: args})

    caller_pid = self()
    Logger.debug("Caller pid: #{inspect(caller_pid)}")

    # Set unique id for request
    correlation_id = Core.uuid_tag(10)

    :ok =
      Producer.publish(
        :whiterabbit_rpc_conn,
        "suzerain.rpcs.exchange",
        "#{service}.rpcs",
        payload,
        reply_to: caller_id,
        correlation_id: correlation_id,
        content_type: "application/json"
      )

    Registry.register(RPCRequestRegistry, correlation_id, caller_id)

    receive do
      {:rpc, value} -> {:ok, value}
    after
      timeout -> {:error, :timeout}
    end
  end

  def return_rpc_message!(channel, message, metadata) do
    %{correlation_id: correlation_id, delivery_tag: delivery_tag} = metadata

    Logger.debug("Handling Returned RPC msg: #{inspect(delivery_tag)}")

    message =
      message
      |> Jason.decode!()

    # get caller process id
    case Registry.lookup(RPCRequestRegistry, correlation_id) do
      [{pid, value}] ->
        Logger.debug("Caller process matched: pid: #{inspect(pid)}, value: #{inspect(value)}")
        :ok = Basic.ack(channel, delivery_tag)
        # send message (returned result) to process id
        send(pid, {:rpc, message})

      [] ->
        Logger.warn("Caller process didnt match, correlation_id: #{inspect(correlation_id)}")
        Basic.reject(channel, delivery_tag, requeue: false)
        {:error, :caller_not_found}
    end
  end

  def handle_rpc_message!(channel, message, metadata) do
    Logger.debug("Receiving RPC msg: #{inspect(metadata.delivery_tag)}")

    response =
      message
      |> decode_rpc_message!(metadata)
      |> process_rpc_message(metadata)
      |> encode_rpc_message!(metadata)

    case response do
      {:ok, resp} ->
        Basic.ack(channel, metadata.delivery_tag)

        Logger.debug("Responding to RPC with: #{inspect(resp)}, to: #{metadata.reply_to}")
        Logger.info("Responding to RPC: #{metadata.reply_to}")

        WhiteRabbit.Producer.publish(
          :whiterabbit_rpc_conn,
          "amq.direct",
          metadata.reply_to,
          resp,
          content_type: "application/json",
          correlation_id: metadata.correlation_id
        )

      _ ->
        Basic.reject(channel, metadata.delivery_tag, requeue: false)
    end
  end

  defp process_rpc_message(%WhiteRabbit.RPC.Message{} = message, metadata) do
    %WhiteRabbit.RPC.Message{
      module: module,
      function: function,
      args: args,
      caller_id: caller_id
    } = message

    Logger.debug("Processing RPC msg: #{inspect(caller_id)}")

    module = String.to_existing_atom(module)
    function = String.to_existing_atom(function)

    result = apply(module, function, args)

    {:ok, result}
  end

  defp decode_rpc_message!(message, metadata) do
    case metadata.content_type do
      "application/json" ->
        message
        |> Jason.decode!()
        |> WhiteRabbit.RPC.Message.convert!()

      _ ->
        message
    end
  end

  defp encode_rpc_message!(data, metadata) do
    with {:ok, result} <- data,
         "application/json" <- metadata.content_type do
      result
      |> Jason.encode()
    else
      _ -> {:error, data}
    end
  end
end
