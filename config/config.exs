import Config

# Configures Elixir's Logger
config :logger, :console, format: "$time $metadata[$level] $message\n"

config :amqp,
  connections: [
    white_rabbit: [
      # See AMQP.Connection.open() for more options
      url: System.get_env("RABBITMQ_URL", "amqp://guest:guest@localhost:5672"),
      name: System.get_env("RABBITMQ_CONN_NAME", "default_app_conn")
    ]
  ],
  channels: [
    white_rabbit_consumer: [connection: :white_rabbit],
    white_rabbit_producer: [connection: :white_rabbit]
  ]

# import_config "#{Mix.env}.exs"
