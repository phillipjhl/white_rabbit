defmodule WhiteRabbit.Fluffle do
  @moduledoc """
  Supervisor of multiple DynamicSupervisors that will handle starting Consumers and Producers.

  FUN FACT: Did you a group of rabbits is called a fluffle? Neither did I.
  """

  use Supervisor
  require Logger

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts, name: __MODULE__)
  end

  @impl true
  def init(opts) do
    children = [
      # Registry for dynamically created consumers/producers
      {Registry, keys: :unique, name: FluffleRegistry},

      # DynamicSupervisor for consumers
      {DynamicSupervisor,
       [name: WhiteRabbit.Fluffle.DynamicSupervisor.Consumer, strategy: :one_for_one]},

      # DynamicSupervisor for producers
      {DynamicSupervisor,
       [name: WhiteRabbit.Fluffle.DynamicSupervisor.Producer, strategy: :one_for_one]}
      # {WhiteRabbit.Consumer,
      #  %WhiteRabbit.Consumer{
      #    name: :JsonConsumer,
      #    exchange: "json_test_exchange",
      #    queue: "json_test_queue",
      #    processor: %WhiteRabbit.Processor.Config{module: Aggie.TestJsonProcessor}
      #  }}
    ]

    Supervisor.init(children, strategy: :one_for_one)
  end
end
