defmodule WhiteRabbit.Fluffle do
  @moduledoc """
  Supervisor of multiple DynamicSupervisors that will handle starting Consumers and Producers.

  Uses a Registry to handle tracking of all the dynamically spawned child processes under this Supervisor.

  FUN FACT: Did you a group of rabbits is called a fluffle? Neither did I.
  """

  use Supervisor
  require Logger

  @type fluffle_option :: {:startup_consumers, {term(), WhiteRabbit.Consumer.t()}}
  @type fluffle_options :: [fluffle_option]

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    startup_consumers = Keyword.get(opts, :startup_consumers, [])

    children =
      [
        # Registry for dynamically created consumers/producers
        {Registry, keys: :unique, name: FluffleRegistry},

        # DynamicSupervisor for consumers
        {DynamicSupervisor,
         [name: WhiteRabbit.Fluffle.DynamicSupervisor.Consumer, strategy: :one_for_one]},

        # DynamicSupervisor for producers
        {DynamicSupervisor,
         [name: WhiteRabbit.Fluffle.DynamicSupervisor.Producer, strategy: :one_for_one]}
      ] ++ startup_consumers

    Supervisor.init(children, strategy: :one_for_one)
  end

  def get_current_children do
    DynamicSupervisor.which_children(WhiteRabbit.Fluffle.DynamicSupervisor.Consumer)
  end
end
