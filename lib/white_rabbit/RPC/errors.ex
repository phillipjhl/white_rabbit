defmodule WhiteRabbit.RPC.ConfigError do
  defexception [:message]

  @impl true
  def exception(value) do
    msg = "RPC not enabled or configured for #{inspect(value)}"
    %WhiteRabbit.RPC.ConfigError{message: msg}
  end
end
