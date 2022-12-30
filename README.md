# White Rabbit

RabbitMQ Elixir library to handle all consuming, producing, and exchanging of RabbitMQ messages.

This lightweight library makes use of the AMQP 0-9-1 protocol. Use WhiteRabbit to help with scaling and processing of your RabbitMQ message queues. 

Whether you need just connection and channel recovery with running processes, or want to take advantage of the RPC call architecture across independent distributed OTP applications with the benefit of having your messages being sent to your RabbitMQ's queues; this library will build upon whatever is required for your application. 

Features:

- RPC call architecture between apps using RabbitMQ and reply_to key routing.
- Auto recovery and restarts of connections, their channels, and the consumers using them
- Startup and runtime support for Consumer GenServer processes. Start them at runtime using Elixir's DynamicSupervisors.
- Telemetry event emission on publishes, acks, and rejects

If this isn't exactly what you are looking for, I recommend the well-known elixir library [broadway](https://github.com/dashbitco/broadway). Even though that is intended for multi-stage data ingest using GenStages and has more batch-level processing in mind, it has similar features that could fit your needs.

## v0.1.0 Topology

![Topology Flow](assets/WhiteRabbit_Topology.svg)

# Implementing

## Add To Dependencies

```elixir
  defp deps do
    [
      {:white_rabbit, "~> 0.2.0"},
    ]
  end
```

## Use As A Behavior

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

The `consume_payload/2` callback is called immediately after a message is received. It should return a `{:ok, AMQP.Basic.delivery_tag()}` tuple if successful or a `{:error, {AMQP.Basic.delivery_tag(), Keyword.t()}}` if not successful so the Consumer can properly send an 'ack' or 'reject' for the message and then let RabbitMQ broker can handle it appropriately (requeue, send to dead-letter-queue, etc.)

See `WhiteRabbit.Processor` for more on the behaviour used.

Example:

```elixir
defmodule AppOne.TestJsonProcessor do
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
        {:error, {tag, [requeue: false]}}
    end
  rescue
    exception ->
      # Requeue unless it's a redelivered message.
      # This means we will retry consuming a message once in case of exception
      # before we give up and have it moved to the error queue
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
      connection_name: :appone_connection,
      name: "AppOne.JsonConsumer",
      exchange: "json_test_exchange",
      queue: "json_test_queue",
      processor: %WhiteRabbit.Processor.Config{module: AppOne.TestJsonProcessor}
      }
    }
  ]
end
```

### Full Example Module

```elixir
defmodule AppOne.WhiteRabbit do
  use WhiteRabbit

  alias WhiteRabbit.{Connection, Core}

  # Define list of connections for this WhiteRabbit instance
  def get_connections do
    [
      %Connection{
        connection_name: :appone_connection,
        conn_opts: [url: "amqp://user:pass@localhost:5673/dev"],
        channels: [
          %{
            name: :appone_consumer_channel
          },
          %{
            name: :appone_producer_channel
          }
        ]
      },
      %Connection{
        connection_name: :appone_rpc_connection,
        conn_opts: [url: "amqp://user:pass@localhost:5673/dev"],
        channels: [
          %{
            name: :appone_rpc_consumer_channel_1
          },
          %{
            name: :appone_rpc_consumer_channel_2
          }
        ]
      }
    ]
  end

  # Use callback spec to return %WhiteRabbit.RPC.Config{} struct
  @impl true
  def get_rpc_config do
    %WhiteRabbit.RPC.Config{
      service_name: :appone,
      connection_name: :appone_rpc_connection
    }
  end

  # Set optional Consumer process to start consuming at app start-up
  @impl true
  def get_startup_consumers do
    [
      {WhiteRabbit.Consumer, %WhiteRabbit.Consumer{
          connection_name: :appone_connection,
          name: "AppOne.JsonConsumer",
          exchange: "json_test_exchange",
          queue: "json_test_queue",
          processor: %WhiteRabbit.Processor.Config{module: AppOne.TestJsonProcessor}
        }
      }
    ]
  end

  def start_link(_opts) do
    rpc_enabled = if Mix.env() !== :test, do: true, else: false

    # Start the WhiteRabbit Hole
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
appone_config = %WhiteRabbit.Consumer{
  owner_module: AppOne.WhiteRabbit,
  connection_name: :appone_connection,
  name: "AppOne.TestJsonProcessor",
  exchange: "json_test_exchange",
  queue: "json_test_queue",
  processor: %WhiteRabbit.Processor.Config{module: AppOne.TestJsonProcessor}
}

apptwo_config = %WhiteRabbit.Consumer{
  owner_module: AppTwo.WhiteRabbit,
  connection_name: :apptwo_connection,
  name: "AppTwo.TestJsonProcessor",
  exchange: "apptwo_json_test_exchange",
  queue: "apptwo_json_test_queue",
  processor: %WhiteRabbit.Processor.Config{module: AppTwo.TestJsonProcessor}
}

AppOne.WhiteRabbit.start_dynamic_consumers(appone_config, 3)
AppTwo.WhiteRabbit.start_dynamic_consumers(apptwo_config, 3)

# or specifying the owner module

WhiteRabbit.start_dynamic_consumers(appone_config, 3, AppOne.WhiteRabbit)
WhiteRabbit.start_dynamic_consumers(apptwo_config, 3, AppTwo.WhiteRabbit)
```

### Publish With Producer Module

See `WhiteRabbit.Producer`

If using the Producer as a behavior there is a providing `publish/5` that you can just provide the connection_name so it will use the correct connection pool and use a channel under that already opened connection.

This method will make sure the channel and connection used are from the calling application which will be under the correct supervision tree.

This is the prefered method especially if there are serveral applications with `WhiteRabbit` modules under an umbrella application.

```elixir
defmodule AppOne.Producer.Json do
  use WhiteRabbit.Producer

  def send_json(payload) do
    publish(:appone_connection, "json_test_exchange", "test_json", payload,
        content_type: "application/json",
        persistent: true
      )
  end
end
```

If you know the channel registry name and the connection name of the pool to use then you can use the `publish/5` function with a tuple as the first argument.

```elixir
WhiteRabbit.Producer.publish({:appone_connection, AppOne.WhiteRabbit.ChannelRegistry}, "test_exchange", "test_route", "hello there", persistent: true)
```

If there is an already connected channel you can use the `publish/5`.

Example:

```elixir
channel = %AMQP.Channel{}

WhiteRabbit.Producer.publish(channel, "test_exchange", "test_route", "hello there", persistent: true)
```

### Test Publish to Exchange

```elixir
WhiteRabbit.Core.test_publish(100, "json_test_exchange", "test_json", %{hello: "there"})
WhiteRabbit.Core.test_publish(100, "apptwo_json_test_exchange", "test_json", %{hello: "there"})
```

### RPC Calls

See `WhiteRabbit.RPC` for more information on RPC calls and message handling.

Using the RPC config shown above, a process can call the function `WhiteRabbit.RPC.call/4` to make an RPC call to the service and get a response back from the server and have it map back correctly to the calling process.

If using as a behavior, then a `rpc_call/3` function will be provided that accepts the service to call, mfa tuple, and options.

Example:

```elixir
iex> AppFour.WhiteRabbit.rpc_call(:appone, {AppOne.Utils, :get_versions, []})
{:ok,
 [
   %{"name" => "appone", "version" => "3.5.0"},
   %{"name" => "custom_lib_1", "version" => "1.3.0"},
   %{"name" => "processing_lib", "version" => "2.6.0"}
 ]}
```

# To Generate ExDocs

```
$ mix docs
```

# Copyright and License

Copyright (c) 2021, Phillip Langland

WhiteRabbit source code is licensed under the [MIT License](./LICENSE).
