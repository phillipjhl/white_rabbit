defmodule WhiteRabbit.RPC do
  @moduledoc """
  RPC module that handles decoding, encoding, and processing of RPC calls.

  #### Start Setup
  Pass the WhiteRabbit `rpc_enabled: true` option as well as the config map via the `rpc_config` option.

  Use the optional WhiteRabbit callback: `WhiteRabbit.get_rpc_config()` to output correct format.

  #### Example Calls

  `iex> Mice.WhiteRabbit.rpc_call(:aggie, {Aggie.Utils, :get_versions, []})`
  """
  require Logger
  require Jason

  alias WhiteRabbit.{Producer, Core}
  alias AMQP.{Basic}

  @typedoc """
  Service that a rpc call will be sent to.

  Ex: "aggie"
  """
  @type service_rpc :: String.t()

  @spec call(
          owner :: module,
          service :: service_rpc,
          mfa :: {module, atom(), []},
          options :: Keyword.t()
        ) ::
          {:ok, any()} | {:error, any()}
  def call(owner, service, mfa, opts \\ []) do
    timeout = Keyword.get(opts, :timeout, 10000)

    # get config to get caller_id and rpc_config
    case :persistent_term.get({WhiteRabbit, owner}) do
      %{
        channel_registry: channel_registry,
        rpc_config: %{reply_id: caller_id, connection_name: rpc_connection_name} = rpc_config,
        rpc_requests_registry: rpc_requests_registry
      } ->
        Logger.debug("#{owner} client reply_id: #{inspect(caller_id)}")

        # Start rpc call task
        task =
          Task.async(fn ->
            make_call(caller_id, service, mfa, timeout,
              conn_tuple: {rpc_connection_name, channel_registry},
              rpc_requests_registry: rpc_requests_registry
            )
          end)

        # Return awaited result with timeout
        Task.await(task, timeout + 1000)

      _ ->
        # Raise error if not rpc configured
        raise WhiteRabbit.RPC.ConfigError, service
        {:error, :rpc_not_configured}
    end
  end

  @spec make_call(
          String.t(),
          service_rpc,
          {module, atom(), []},
          timeout :: integer(),
          opts :: Keyword.t()
        ) ::
          {:ok, any()} | {:error, any()}
  defp make_call(caller_id, service, mfa, timeout, opts \\ []) do
    conn_tuple = Keyword.get(opts, :conn_tuple, nil)
    rpc_requests_registry = Keyword.get(opts, :rpc_requests_registry, RPCRequestRegistry)

    Logger.debug("Registry: #{rpc_requests_registry}")

    {module, func, args} = mfa

    # namespaced_module = get_namespaced_string(service, module, prefix: true)

    payload =
      Jason.encode!(%WhiteRabbit.RPC.Message{
        caller_id: caller_id,
        module: module,
        function: func,
        args: args
      })

    caller_pid = self()
    Logger.debug("Caller pid: #{inspect(caller_pid)}")

    # Set unique id for request
    correlation_id = Core.uuid_tag(10)

    :ok =
      Producer.publish(
        conn_tuple,
        "suzerain.rpcs.exchange",
        "#{service}.rpcs",
        payload,
        reply_to: caller_id,
        correlation_id: correlation_id,
        content_type: "application/json",
        # set app_id to process registry name
        app_id: "#{rpc_requests_registry}",
        type: "rpc.call"
      )

    Registry.register(rpc_requests_registry, correlation_id, caller_id)

    receive do
      {:rpc, value} -> {:ok, value}
    after
      timeout -> {:error, :timeout}
    end
  end

  def return_rpc_message!(channel, message, metadata) do
    %{correlation_id: correlation_id, delivery_tag: delivery_tag, app_id: app_id} = metadata

    Logger.debug("Handling Returned RPC msg: #{inspect(delivery_tag)}")
    Logger.debug("App Registry: #{inspect(app_id)}")

    registry = String.to_existing_atom(app_id)

    message =
      message
      |> Jason.decode!()

    # get caller process id
    case Registry.lookup(registry, correlation_id) do
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

    Logger.debug("Encoded RPC Response: #{inspect(response)}")

    case response do
      {:ok, resp} ->
        Logger.debug("Responding to RPC with: #{inspect(resp)}, to: #{metadata.reply_to}")
        Logger.info("Responding to RPC: #{metadata.reply_to}")

        WhiteRabbit.Producer.publish(
          channel,
          "amq.direct",
          metadata.reply_to,
          resp,
          content_type: "application/json",
          correlation_id: metadata.correlation_id,
          type: "rpc.reply",
          # set app_id to process registry name from original call
          app_id: metadata.app_id
        )

        Basic.ack(channel, metadata.delivery_tag)

      _ ->
        Logger.warn("Rejecting RPC message: #{inspect(metadata.delivery_tag)}")
        Basic.reject(channel, metadata.delivery_tag, requeue: false)
    end
  end

  defp process_rpc_message(%WhiteRabbit.RPC.Message{} = message, _metadata) do
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

    Logger.debug("RPC result: #{inspect(result)}")

    {:ok, result}
  end

  defp decode_rpc_message!(message, metadata) do
    case metadata.content_type do
      "application/json" ->
        message
        |> Jason.decode!()
        |> WhiteRabbit.RPC.Message.convert!()

      error ->
        Logger.error("RPC Decode error: #{inspect(error)}")
        message
    end
  end

  defp encode_rpc_message!(data, metadata) do
    with {:ok, result} <- data,
         "application/json" <- metadata.content_type do
      result
      |> Jason.encode()
    else
      error ->
        Logger.error("RPC Encode error: #{inspect(error)}")
        {:error, data}
    end
  end

  defp get_namespaced_string(namespace, module, opts \\ []) do
    prefix = Keyword.get(opts, :prefix, false)
    namespace = namespace |> Atom.to_string() |> String.capitalize()

    namespaced_module =
      if prefix, do: "Elixir.#{namespace}.#{module}", else: "#{namespace}.#{module}"

    namespaced_module
  end
end
