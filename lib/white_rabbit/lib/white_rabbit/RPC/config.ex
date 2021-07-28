defmodule WhiteRabbit.RPC.Config do
  @moduledoc """
  RPC config struct given at app startup to configure the service consumer, replies consumer, and register it under the service_name.
  """

  @enforce_keys [:service_name, :connection_name]
  defstruct service_consumer: nil,
            replies_consumer: nil,
            service_name: nil,
            reply_id: nil,
            connection_name: nil

  @type t :: %__MODULE__{
          service_consumer: WhiteRabbit.Consumer.t(),
          replies_consumer: WhiteRabbit.Consumer.t(),
          service_name: atom(),
          connection_name: atom()
        }
end
