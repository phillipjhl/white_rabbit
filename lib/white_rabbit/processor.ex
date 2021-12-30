defmodule WhiteRabbit.Processor do
  @moduledoc """
  Processor behavior that modules can use to implememnt common callbacks to consume message payloads.

  To use:

  ```
  defmodule MyApp.JsonMessageProcessor do
    @behaviour WhiteRabbit.Processor

    def consumer_payload(payload, meta) do
      %{delivery_tag: tag, redelivered: redelivered} = meta

      case content_type do
        "application/json" ->
          {:ok, _json} = Jason.decode(payload)

          # If successful, send back `{:ok, AMQP.Basic.delivery_tag()}`
          {:ok, tag}

        _ ->
          {:error, :things_went_south}
      end
    end
  end
  ```
  """

  alias AMQP.{Basic}

  @type processor_payload :: any()
  @type processor_meta :: map()
  @type tag :: Basic.delivery_tag()

  @type consume_error :: {:error, {tag(), keyword()}}

  @doc """
  Callback function to process payload from a message.

  Must return {:ok, delivery_tag()} tuple to allow for proper ack.

  Or {:error, reason} tuple for rejects.
  """
  @callback consume_payload(processor_payload(), processor_meta()) ::
              {:ok, tag()} | consume_error()

  @callback handle_after_ack() :: {:ok, any()} | {:error, any()}

  @callback handle_after_reject() :: {:ok, any()} | {:error, any()}

  @optional_callbacks handle_after_ack: 0, handle_after_reject: 0
end
