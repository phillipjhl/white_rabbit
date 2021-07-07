# White Rabbit

RabbitMQ Elixir library to handle all consuming, producing, and exchanging of RabbitMQ messages.

# Implementing

## Add To Dependencies

```elixir
  defp deps do
    [
      {:white_rabbit, path: "path/to/project"},
    ]
  end
```

## Use As A Behavior:

```elixir
# In MyApp

defmodule MyApp.WhiteRabbit do
  use WhiteRabbit

  def start_link(_opts) do
    WhiteRabbit.start_link(__MODULE__, name: __MODULE__)
  end

  # Callbacks below
end
```

```elixir
# In Main Application Supervisor

children = [
  # other fun stuff...
  {MyApp.WhiteRabbit, []}
]

Supervisor.start_link(children, opts)
```

### Define Processor Modules

`WhiteRabbit.Processor` Behaviour is used to define how a `WhiteRabbit.Consumer` Genserver will process the messages that it receives once it is registered to a RabbitMQ queue.

The `consume_payload/2` callback is called immediately after a message is received. It should return a `{:ok, any()}` tuple of a `WhiteRabbit.Processor.consume_error()` so the Consumer can properly send an acknowledgemnet or reject for the message so RabbitMQ broker can handle it.

See `WhiteRabbit.Processor` for more on the behaviour used.

Example:

```elixir
defmodule Aggie.TestJsonProcessor do
  @behaviour WhiteRabbit.Processor

  require Logger

  @impl true
  def consume_payload(
        payload,
        %{delivery_tag: tag, redelivered: redelivered, content_type: content_type} = meta
      ) do
    Logger.debug("Processing message #{tag} with #{__MODULE__}")

    case content_type do
      "application/json" ->
        {:ok, _json} = Jason.decode(payload)

        # If successful, send back `{:ok, AMQP.Basic.delivery_tag()}`
        {:ok, tag}

      _ ->
        # Requeue unless it's a redelivered message.
        # This means we will retry consuming a message once in case of exception
        # before we give up and have it moved to the error queue
        {:error, {tag, [requeue: false]}}
    end
  rescue
    exception ->
      Logger.warn("Error consuming message: #{tag} #{inspect(exception)}")
      {:error, {tag, [requeue: not redelivered]}}
  end
end
```

### Define Optional Startup Consumers

See `WhiteRabbit.Consumer` for more info.

```elixir
@impl true
def get_startup_consumers do
  [
    {WhiteRabbit.Consumer, %WhiteRabbit.Consumer{
      connection_name: :aggie_connection,
      name: "Aggie.JsonConsumer",
      exchange: "json_test_exchange",
      queue: "json_test_queue",
      processor: %WhiteRabbit.Processor.Config{module: Aggie.TestJsonProcessor}
      }
    }
  ]
end
```

### Full Example Module

```elixir
defmodule Aggie.WhiteRabbit do
  use WhiteRabbit

  alias WhiteRabbit.{Connection, Core}

  # Define list of connections for this WhiteRabbit instance
  def connections do
    [
      %Connection{
        connection_name: :aggie_connection,
        conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
        channels: [
          %{
            name: :aggie_consumer_channel
          },
          %{
            name: :aggie_producer_channel
          }
        ]
      },
      %Connection{
        connection_name: :aggie_rpc_connection,
        conn_opts: [url: "amqp://suzerain:suzerain@localhost:5673/dev"],
        channels: [
          %{
            name: :aggie_rpc_consumer_channel_1
          },
          %{
            name: :aggie_rpc_consumer_channel_2
          }
        ]
      }
    ]
  end

  # Use callback spec to return %WhiteRabbit.RPC.Config{} struct
  @impl true
  def get_rpc_config do
    reply_id = Core.uuid_tag()

    %WhiteRabbit.RPC.Config{
      service_consumer: %WhiteRabbit.Consumer{
        connection_name: :aggie_rpc_connection,
        name: "Aggie.RPC.Receiver",
        exchange: "suzerain.rpcs.exchange",
        queue: "aggie.rpcs",
        queue_opts: [auto_delete: true],
        binding_keys: ["aggie.rpcs"],
        error_queue: false,
        processor: %WhiteRabbit.Processor.Config{
          module: WhiteRabbit.RPC,
          function: :handle_rpc_message!
        }
      },
      replies_consumer: %WhiteRabbit.Consumer{
        connection_name: :aggie_rpc_connection,
        name: "Aggie.RPC.Replies",
        exchange: "amq.direct",
        exchange_type: :direct,
        queue: "aggie.rpcs.replies.#{reply_id}",
        queue_opts: [auto_delete: true, durable: false, exclusive: true],
        binding_keys: ["#{reply_id}"],
        error_queue: false,
        processor: %WhiteRabbit.Processor.Config{
          module: WhiteRabbit.RPC,
          function: :return_rpc_message!
        }
      },
      service_name: "aggie",
      reply_id: reply_id
    }
  end

  @impl true
  def get_startup_consumers do
    [
{WhiteRabbit.Consumer, %WhiteRabbit.Consumer{
      connection_name: :aggie_connection,
      name: "Aggie.JsonConsumer",
      exchange: "json_test_exchange",
      queue: "json_test_queue",
      processor: %WhiteRabbit.Processor.Config{module: Aggie.TestJsonProcessor},
      prefetch_count: 50
      }
    }
    ]
  end

  def start_link(_opts) do
    rpc_enabled = if Mix.env() !== :test, do: true, else: false

    WhiteRabbit.start_link(__MODULE__,
      name: __MODULE__,
      connections: connections(),
      rpc_enabled: rpc_enabled,
      rpc_config: get_rpc_config()
    )
  end
end

```

## Testing

### Starting Dynamic Consumers

The processor module needs to exist before trying to register a consumer for it.

See `WhiteRabbit.Processor` module for more info on that behaviour

```elixir
aggie_config = %WhiteRabbit.Consumer{
  name: "Aggie.TestJsonProcessor",
  exchange: "json_test_exchange",
  queue: "json_test_queue",
  processor: %WhiteRabbit.Processor.Config{module: Aggie.TestJsonProcessor}
}

jeopardy_config = %WhiteRabbit.Consumer{
  name: "Jeopardy.TestJsonProcessor",
  exchange: "jeopardy_json_test_exchange",
  queue: "jeopardy_json_test_queue",
  processor: %WhiteRabbit.Processor.Config{module: Jeopardy.TestJsonProcessor}
}

WhiteRabbit.Consumer.test_start_dynamic_consumers(aggie_config, 3)
WhiteRabbit.Consumer.test_start_dynamic_consumers(jeopardy_config, 3)
```

### Publish With Producer Module
See `WhiteRabbit.Producer`

```elixir
WhiteRabbit.Producer.publish(:aggie_connection, "test_exchange", "test_route", "hello there", persistent: true)
```
### Test Publish to Exchange

```elixir
WhiteRabbit.Core.test_publish(100, "json_test_exchange", "test_json", %{hello: "there"})
WhiteRabbit.Core.test_publish(100, "jeopardy_json_test_exchange", "test_json", %{hello: "there"})
```


### RPC Calls

See `WhiteRabbit.RPC` for more information on RPC calls and message handling.

# To Generate ExDocs

```
$ mix docs
```

# To Do

- [ ] Runtime config from external data source
  - [ ] Config should be configured/handled externally. This library should just accept a standard data set of config maps for runtime setup.

- [ X ] Consumer and Producer Dynamic Supervisor topology
- [ X ] RPC control flow
      Concept:
      ![RPC Concept](assets/WhiteRabbitRPCFlowGraph-05112021.png)

- [ ] Auto-scaling of event processing with `L = lw`

  ```
  L - # of msgs
  l - rate of arrival
  w - avg time it takes to process 1 message

  Kill/Spawn new processer module to keep a constant time performance level
  ```

- [ ] Telemetry event emission
  - [ X ] publish events
  - [ ] consume events
