defmodule WhiteRabbit.RPC.Config do
  @moduledoc """
  RPC config struct given at app startup to configure the service consumer, replies consumer, and register it under the service_name.
  """

  @enforce_keys [:service_consumer, :replies_consumer, :service_name, :reply_id]
  defstruct service_consumer: nil, replies_consumer: nil, service_name: nil, reply_id: nil

  @type t :: %__MODULE__{
          service_consumer: WhiteRabbit.Consumer.t(),
          replies_consumer: WhiteRabbit.Consumer.t(),
          service_name: String.t(),
          reply_id: String.t()
        }
end
