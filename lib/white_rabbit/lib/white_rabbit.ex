defmodule WhiteRabbit do
  @moduledoc false

  use Application
  require Logger

  # See http://elixir-lang.org/docs/stable/elixir/Application.html
  # for more information on OTP Applications
  def start(_type, _args) do
    Confex.resolve_env!(:white_rabbit)

    children = [
      # Rabbit Default Supervisor, define further children there
      {WhiteRabbit.Supervisor, []}
    ]

    opts = [strategy: :rest_for_one, name: WhiteRabbit.MainSupervisor]

    Supervisor.start_link(children, opts)
  end
end
