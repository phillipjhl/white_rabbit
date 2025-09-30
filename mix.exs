defmodule WhiteRabbit.Mixfile do
  use Mix.Project

  def project do
    [
      app: :white_rabbit,
      description: description(),
      version: "0.2.1",
      elixir: "~> 1.6",
      build_path: "_build",
      config_path: "config/config.exs",
      deps_path: "deps",
      lockfile: "mix.lock",
      build_embedded: Mix.env() == :prod,
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      package: package(),
      name: "White Rabbit",
      source_url: "https://github.com/phillipjhl/white_rabbit",
      docs: [
        assets: %{"assets/" => "assets"},
        main: "readme",
        extras: ["README.md", "LICENSE"],
        authors: ["(@phillipjhl) Phillip Langland"],
        javascript_config_path: "./hex-docs.js"
      ]
    ]
  end

  # Configuration for the OTP application
  #
  # Type "mix help compile.app" for more information
  def application do
    # Specify extra applications you'll use from Erlang/Elixir
    [
      extra_applications: [:logger, :amqp]
    ]
  end

  # Dependencies can be Hex packages:
  #
  #   {:my_dep, "~> 0.3.0"}
  #
  # Or git/path repositories:
  #
  #   {:my_dep, git: "https://github.com/elixir-lang/my_dep.git", tag: "0.1.0"}
  #
  # Type "mix help deps" for more examples and options
  defp deps do
    [
      {:amqp, "~> 4.1"},
      {:jason, "~> 1.0"},
      {:telemetry, "~> 1.3.0"},
      {:ex_doc, "~> 0.24", only: :dev, runtime: false},
      {:credo, "~> 1.7.0", only: :dev, runtime: false}
    ]
  end

  def description() do
    "Library to handle all consuming, producing, and exchanging of RabbitMQ messages via AMQP 0-9-1 protocol. Also enables RPC across independent OTP apps over RabbitMQ queues."
  end

  def package() do
    [
      licenses: ["MIT"],
      links: %{"github" => "https://github.com/phillipjhl/white_rabbit"}
    ]
  end
end
