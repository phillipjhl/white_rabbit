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

      defoverridable child_spec: 1
    end
  end

  @typedoc """
  Returned by `start_link/2`.
  """
  @type on_start() :: {:ok, pid()} | :ignore | {:error, {:already_started, pid()} | term()}

  def get_config(app) do
    [%{}]
  end

  @callback get_config(atom()) :: [%{}]

  @optional_callbacks get_config: 1

  @doc """
  Start the WhiteRabbit.
  """
  # @spec start_link(module(), keyword()) :: on_start()
  def start_link(module, opts) do
    WhiteRabbit.Hole.start_link({module, opts})
  end
end
