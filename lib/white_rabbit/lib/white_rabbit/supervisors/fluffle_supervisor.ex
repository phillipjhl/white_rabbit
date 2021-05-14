defmodule WhiteRabbit.Fluffle do
  @moduledoc """
  Supervisor of multiple DynamicSupervisors that will handle starting Consumers and Producers.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      {DynamicSupervisor,
       [name: WhiteRabbit.Fluffle.DynamicSupervisor.Consumer, strategy: :one_for_one]},
      {DynamicSupervisor,
       [name: WhiteRabbit.Fluffle.DynamicSupervisor.Producer, strategy: :one_for_one]}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
