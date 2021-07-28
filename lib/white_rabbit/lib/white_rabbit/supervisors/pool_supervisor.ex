defmodule WhiteRabbit.PoolSupervisor do
  @moduledoc """
  Supervisor of multiple `WhiteRabbit.ChannelsAndConnSupervisor`.

  The strategy is set to `:one_for_one` so each `WhiteRabbit.ChannelsAndConnSupervisor` can handle its own connection and channels.

  This Supervisor allows for decouling of each connection and their respective channels from the rest of the topology.
  """

  use Supervisor
  require Logger

  alias WhiteRabbit.{ChannelsAndConnSupervisor}

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    connections = Keyword.get(opts, :connections, [])
    name = Keyword.get(opts, :name, __MODULE__)
    module = Keyword.get(opts, :module, WhiteRabbit)

    children =
      Enum.map(connections, fn conn ->
        Supervisor.child_spec({ChannelsAndConnSupervisor, [module: module, connection: conn]},
          id: "#{name}.ChannelsAndConnSupervisor:#{conn.connection_name}"
        )
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
