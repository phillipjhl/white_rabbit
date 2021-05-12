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

## Behavior:

```elixir
# In MyApp

defmodule MyApp.WhiteRabbit do
    use WhiteRabbit
end
```

## To Do

- [ ] Runtime config from external data source
- [ ] RPC control flow
- [ ] Auto-scaling of event processing
- [ ] Add core connection and channel supervisor topology
- [ ] Consumer and Producer Dynamic Supervisor topology