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

## To Do

- [ ] Runtime config from external data source
- [ ] Consumer and Producer Dynamic Supervisor topology
- [ ] RPC control flow
  Concept:
  ![RPC Concept](assets/WhiteRabbitRPCFlowGraph-05112021.png)

- [ ] Auto-scaling of event processing with `L = lw`
    ```
    L - # of msgs
    l - rate of arrival
    w - avg time it takes to process 1 message

    Kill/Spawn new processer module to keep a constant time performance level 
  ```