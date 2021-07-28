defmodule WhiteRabbit.Fluffle do
  @moduledoc """
  Supervisor of multiple DynamicSupervisors that will handle starting Consumers and Producers.

  Uses a Registry to handle tracking of all the dynamically spawned child processes under this Supervisor.

  Pass a `startup_consumers: []` option to `start_link` to allow for start-up Consumers instead of being supervised by
  one of the DynamicSupervisors.

  FUN FACT: Did you a group of rabbits is called a fluffle? Neither did I.
  """

  use Supervisor
  require Logger

  @type fluffle_option :: {:startup_consumers, {term(), WhiteRabbit.Consumer.t()}}
  @type fluffle_options :: [fluffle_option]

  def start_link(opts) do
    name = Keyword.get(opts, :name, __MODULE__)
    Supervisor.start_link(__MODULE__, opts, name: name)
  end

  @impl true
  def init(opts) do
    startup_consumers = Keyword.get(opts, :startup_consumers, [])
    module = Keyword.get(opts, :module, WhiteRabbit)
    registry_name = Keyword.get(opts, :registry_name, WhiteRabbit.Fluffle.FluffleRegistry)

    consumer_supervisor_name = module.process_name("Fluffle.DynamicSupervisor.Consumer")
    producer_supervisor_name = module.process_name("Fluffle.DynamicSupervisor.Producer")

    children =
      [
        # Registry for dynamically created consumers/producers
        {Registry, keys: :unique, name: registry_name},

        # DynamicSupervisor for consumers
        {DynamicSupervisor, [name: consumer_supervisor_name, strategy: :one_for_one]},

        # DynamicSupervisor for producers
        {DynamicSupervisor, [name: producer_supervisor_name, strategy: :one_for_one]}
      ] ++ startup_consumers

    Supervisor.init(children, strategy: :one_for_one)
  end

  @doc """
  Uses `DynamicSupervisor.which_children()` to output list of childrend on the `WhiteRabbit.Fluffle` Supervisor.
  """
  def get_current_children(module) do
    DynamicSupervisor.which_children(module)
  end
end
