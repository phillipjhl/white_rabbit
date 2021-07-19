defmodule WhiteRabbit do
  @doc false
  defmacro __using__(opts) do
    quote location: :keep, bind_quoted: [opts: opts, module: __CALLER__.module] do
      @behaviour WhiteRabbit

      @doc false
      def child_spec(arg) do
        default = %{
          id: unquote(module),
          start: {__MODULE__, :start_link, [arg]},
          shutdown: :infinity,
          type: :supervisor
        }

        Supervisor.child_spec(default, unquote(Macro.escape(opts)))
      end

      @doc """
      Returns a map of the full supervisor tree and their children of the given supervisor.

      Uses `Supervisor.which_children/1` recursively.
      """
      @spec get_full_topology(supervisor :: term()) :: map()
      def get_full_topology(supervisor \\ __MODULE__) do
        parent = Supervisor.which_children(supervisor)

        if !Enum.empty?(parent) do
          children_map =
            Enum.group_by(
              parent,
              fn elem ->
                {id, _, _, _} = elem
                id
              end,
              fn elem ->
                {_name, child_pid, type, _module} = elem

                if type === :supervisor do
                  get_full_topology(child_pid)
                else
                  elem
                end
              end
            )
        end
      end

      defoverridable child_spec: 1
    end
  end

  @typedoc """
  Returned by `start_link/2`.
  """
  @type on_start() :: {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}

  @doc """
  Returns a map of a rpc_config to configure the correct rpc queues and consumers.

  Example
  ```elixir

  # Use callback spec to return %WhiteRabbit.RPC.Config{} struct
  @impl true
  def get_rpc_config do
    reply_id = Core.uuid_tag()

    %WhiteRabbit.RPC.Config{
      service_consumer: %WhiteRabbit.Consumer{
        connection_name: :aggie_rpc_connection,
        name: "Aggie.RPC.Receiver",
        exchange: "suzerain.rpcs.exchange",
        queue: "aggie.rpcs",
        queue_opts: [auto_delete: true],
        binding_keys: ["aggie.rpcs"],
        error_queue: false,
        processor: %WhiteRabbit.Processor.Config{
          module: WhiteRabbit.RPC,
          function: :handle_rpc_message!
        }
      },
      replies_consumer: %WhiteRabbit.Consumer{
        connection_name: :aggie_rpc_connection,
        name: "Aggie.RPC.Replies",
        exchange: "amq.direct",
        exchange_type: :direct,
        queue: "aggie.rpcs.replies.\#{reply_id}",
        queue_opts: [auto_delete: true, durable: false, exclusive: true],
        binding_keys: ["\#{reply_id}"],
        error_queue: false,
        processor: %WhiteRabbit.Processor.Config{
          module: WhiteRabbit.RPC,
          function: :return_rpc_message!
        }
      },
      service_name: "aggie",
      reply_id: reply_id
    }
  end
  ```
  """
  @callback get_rpc_config() :: WhiteRabbit.RPC.Config.t()

  @doc """
  Returns a list of tuples defining `WhiteRabbit.Consumer` GenServers to be started on app startup.

  Example
  ```elixir
    def connections do
    [
      %Connection{
        connection_name: :aggie_connection,
        conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
        channels: [
          %{
            name: :aggie_consumer_channel
          },
          %{
            name: :aggie_producer_channel
          }
        ]
      },
      %Connection{
        connection_name: :aggie_rpc_connection,
        conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
        channels: [
          %{
            name: :aggie_rpc_consumer_channel_1
          },
          %{
            name: :aggie_rpc_consumer_channel_2
          }
        ]
      }
    ]
  end
  ```
  """
  @callback get_startup_consumers() :: [{any(), WhiteRabbit.Consumer.t()}]

  @optional_callbacks get_rpc_config: 0, get_startup_consumers: 0

  @doc """
  Start the WhiteRabbit Hole.

  Calls `WhiteRabbit.Hole.start_link` to start the supervision topology defined.
  """
  # @spec start_link(module(), keyword()) :: on_start()
  def start_link(module, opts) do
    WhiteRabbit.Hole.start_link({module, opts})
  end
end
