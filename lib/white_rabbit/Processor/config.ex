defmodule WhiteRabbit.Processor.Config do
  @moduledoc """
  Module for defining a `WhiteRabbit.Processor` configuration struct.

  RPC Example:
  ```
  %WhiteRabbit.Processor.Config{module: RPC, function: :handle_rpc_message!}
  ```
  """

  @enforce_keys [:module]
  defstruct module: nil, function: nil

  @typedoc """
    * module - Module that implements the `WhiteRabbit.Processor` behaviour
    * function - Optional function name atom to support generic processor behavior
  """
  @type t :: %__MODULE__{
          module: module(),
          function: atom()
        }
end
