defmodule WhiteRabbit.ChannelsAndConnSupervisor do
  @moduledoc """
  Supervisor of 1 `WhiteRabbit.Connection` and 1 `WhiteRabbit.ChannelSupervisor`

  Has startegy :rest_for_one so if the `WhiteRabbit.Connection` dies, the connection will be restarted along with all the channels associated with the `WhiteRabbit.ChannelSupervisor`.

  If only one channel dies, this supervisor doesn't care as that's the job of the `WhiteRabbit.ChannelSupervisor`.
  """
  use Supervisor

  alias WhiteRabbit.{ChannelSupervisor, Connection, Channel}

  defstruct connection: nil,
            channels: []

  @type t :: %__MODULE__{connection: atom(), channels: [Channel.t()]}

  def start_link(opts) do
    Supervisor.start_link(__MODULE__, opts)
  end

  @impl true
  def init(
        %Connection{connection_name: connection_name, conn_opts: conn_opts, channels: channels} =
          opts
      ) do
    children = [
      # 1 WhiteRabbit.Connection
      {WhiteRabbit.Connection, opts},
      # 1 WhiteRabbits.ChannelSupervisor
      {ChannelSupervisor, %{connection: connection_name, channels: channels}}
    ]

    Supervisor.init(children, strategy: :rest_for_one)
  end
end
