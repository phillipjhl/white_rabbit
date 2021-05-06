defmodule WhiteRabbit.Supervisor do
  @moduledoc """
  WhiteRabbit Supervisor to monitor all consumers and/or producers.
  """
  use Supervisor

  def start_link(arg) do
    Supervisor.start_link(__MODULE__, arg, name: __MODULE__)
  end

  @impl true
  def init(arg) do
    additional_children = Keyword.get(arg, :children, [])

    children =
      [
        %{
          id: :WhiteRabbitDefaultConsumer,
          start:
            {WhiteRabbit.Consumer, :start_link,
             [
               %WhiteRabbit.Consumer{
                 name: :WhiteRabbitDefaultConsumer,
                 exchange: "WhiteRabbitDefault_exchange",
                 queue: "WhiteRabbitDefault_queue",
                 binding_keys: ["whiterabbit.default.#"]
               }
             ]}
        }
      ] ++ additional_children

    Supervisor.init(children, strategy: :one_for_one)
  end
end
