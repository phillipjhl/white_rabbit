defmodule WhiteRabbit.RPC.ProcessStore do
  @doc """
  GenServer implementation of a key value store using :ets tables to store caller id and their pids to link RPC requests back to
  the correct process.

  Start under a Supervisor.
  ```
  {WhiteRabbit.RPC.ProcessStore, []}
  ```
  """

  use GenServer

  def start_link(opts) do
    table_name = Keyword.get(opts, :table_name, :rpc_store)
    service_name = Keyword.get(opts, :service_name, nil)
    reply_id = Keyword.get(opts, :reply_id, nil)

    init = %{table_name: table_name, reply_id: reply_id, service_name: service_name}

    GenServer.start_link(__MODULE__, init, opts)
  end

  def create_table(name \\ :rpc_store) when is_atom(name) do
    :ets.new(name, [:named_table, read_concurrency: true])
  end

  @spec fetch_id(term()) :: {:ok, any()} | {:error, nil}
  def fetch_id(key, table \\ :rpc_store) do
    case :ets.lookup(table, key) do
      [{^key, value}] -> {:ok, value}
      [] -> {:error, nil}
    end
  end

  def insert(name, key, value) do
    :ets.insert(name, {key, value})
  end

  @spec get_config_for_service(atom()) :: any()
  @doc """
  Get a value from :persistent_term using key `{WhiteRabbit, service}`
  """
  def get_config_for_service(service) do
    :persistent_term.get({WhiteRabbit, service})
  end

  #### GenServer ####

  @impl true
  def init(arg) do
    processes_table = create_table(arg.table_name)

    # If there is a service name, insert the unique id associated with it in the table
    if arg.service_name do
      insert(processes_table, arg.service_name, arg.reply_id)
    end

    refs = %{}
    {:ok, {processes_table, refs}}
  end

  @impl true
  def handle_info({:DOWN, ref, :process, _pid, _reason}, {processes_table, refs}) do
    {name, refs} = Map.pop(refs, ref)
    :ets.delete(processes_table, name)
    {:noreply, {processes_table, refs}}
  end

  @impl true
  def handle_info(_msg, state) do
    {:noreply, state}
  end
end
