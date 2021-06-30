defmodule WhiteRabbit.Processor.Config do
  @moduledoc """
  Module for defining a `WhiteRabbit.Processor` configuration.

  """

  @enforce_keys [:module]
  defstruct module: nil, function: nil

  @typedoc """
    * module - Module that implements the `WhiteRabbit.Processor` behaviour
  """
  @type t :: %__MODULE__{
          module: module(),
          function: atom()
        }
end
