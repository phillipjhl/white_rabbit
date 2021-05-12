defmodule WhiteRabbit.PoolSupervisor do
  @moduledoc """
  Supervisor of multiple `WhiteRabbits.ChannelsAndConnSupervisor`.
  """

  use Supervisor
  require Logger

  alias WhiteRabbit.{ChannelsAndConnSupervisor}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    connections = Keyword.get(opts, :connections, [])

    children =
      Enum.map(connections, fn conn ->
        {ChannelsAndConnSupervisor, conn}
      end)

    Supervisor.init(children, strategy: :one_for_one)
  end
end
