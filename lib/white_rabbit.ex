defmodule WhiteRabbit do
  @moduledoc File.read!("README.md")

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

      def process_name(name, prefix \\ unquote(module)) do
        :"#{prefix}.#{name}"
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

      @doc """
      Make an rpc call to a service with the given mfa tuple

      Example:

      ```
        MyApp.WhiteRabbit.rpc_call(:other_rpc_enabled_service, {OtherApp.Utils, :get_versions, []})
      ```
      """
      @spec rpc_call(atom(), {module(), atom(), []}, Keyword.t()) ::
              {:ok, term()} | {:error, term()}
      def rpc_call(service, mfa, opts \\ []) do
        WhiteRabbit.RPC.call(unquote(module), service, mfa, opts)
      end

      @doc """
      Start a number of Consumer with the given config.

      Pass a `WhiteRabbit.Consumer{}` to start it under an apps's `WhiteRabbit.Fluffle` DynamicSupervisor.

      Optionally pass an integer as the second argument to start any number of Consumers with the same config.

      Optionally pass a module of the owning `WhiteRabbit` module. e.g. AppOne.WhiteRabbit
      - Defaults to this module.
      """
      @spec start_dynamic_consumers(
              config :: Consumer.t(),
              concurrency :: integer(),
              owner_module :: module()
            ) :: [
              tuple()
            ]
      def start_dynamic_consumers(config, concurreny \\ 1, module \\ unquote(module)) do
        WhiteRabbit.Consumer.start_dynamic_consumers(config, concurreny, module)
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
    %WhiteRabbit.RPC.Config{
      service_name: "appone",
      connection_name: :appone_rpc_connection
    }
  end
  ```
  """
  @callback get_rpc_config() :: WhiteRabbit.RPC.Config.t()

  @doc """
  Returns a list of tuples defining `WhiteRabbit.Consumer` GenServers to be started on app startup.

  Example
  ```elixir
  @impl true
  def get_startup_consumers do
    [
      {WhiteRabbit.Consumer,
       %WhiteRabbit.Consumer{
         connection_name: :appone_connection,
         name: "AppOne.JsonConsumer",
         exchange: "json_test_exchange",
         queue: "json_test_queue",
         processor: %WhiteRabbit.Processor.Config{module: AppOne.TestJsonProcessor}
       }}
    ]
  end
  ```
  """
  @callback get_startup_consumers() :: [{any(), WhiteRabbit.Consumer.t()}]

  @doc """
  Returns a list of connections to start.any()

  Example:

  ```elixir
  def get_connections do
    [
      %Connection{
        connection_name: :appone_connection,
        conn_opts: [url: "amqp://user:pass@localhost:5673/dev"],
        channels: [
          %{
            name: :appone_consumer_channel
          },
          %{
            name: :appone_producer_channel
          }
        ]
      },
      %Connection{
        connection_name: :appone_rpc_connection,
        conn_opts: [url: "amqp://user:pass@localhost:5673/dev"],
        channels: [
          %{
            name: :appone_rpc_consumer_channel_1
          },
          %{
            name: :appone_rpc_consumer_channel_2
          }
        ]
      }
    ]
  end
  ```
  """
  @callback get_connections() :: [WhiteRabbit.Connection.t()]

  @callback process_name(String.t(), module()) :: atom()
  def process_name(name, prefix \\ __MODULE__) do
    :"#{prefix}.#{name}"
  end

  @callback start_dynamic_consumers(map(), integer) :: [{:ok, pid()}]
  def start_dynamic_consumers(config, concurreny \\ 1, module \\ __MODULE__) do
    WhiteRabbit.Consumer.start_dynamic_consumers(config, concurreny, module)
  end

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
