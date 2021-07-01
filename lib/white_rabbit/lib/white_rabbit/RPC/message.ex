defmodule WhiteRabbit.RPC.Message do
  @moduledoc """
  RPC message modlue that defines a struct and convert functions.

  """

  @enforce_keys [:module, :function, :args, :caller_id]
  defstruct module: nil, function: nil, args: nil, caller_id: nil

  def convert!(data) when is_map(data) do
    %__MODULE__{
      module: data["module"],
      function: data["function"],
      args: data["args"],
      caller_id: data["caller_id"]
    }
  end

  def convert!(data) do
    data
  end
end
