defmodule Heartwood.MixProject do
  use Mix.Project

  def project do
    [
      app: :heartwood,
      version: "0.1.0",
      elixir: "~> 1.11",
      start_permanent: Mix.env() == :prod,
      deps: deps()
    ]
  end

  def application do
    [
      extra_applications: [:logger],
      mod: {Heartwood.Application, [env: Mix.env()]}
    ]
  end

  defp deps do
    [
      {:cubdb, "~> 1.0.0-rc.6"},
      {:decimal, "~> 2.0"},
      {:elixir_uuid, "~> 1.2"},
      {:logger_file_backend, ">= 0.0.0"},
      {:phoenix_pubsub, "~> 2.0"},
      {:axil, git: "https://git.sr.ht/~dcrck/axil"},
      {:alpaca_elixir, git: "https://git.sr.ht/~dcrck/alpaca-elixir"},
      {:jason, ">= 1.0.0"},
      # Base client
      {:tesla, "~> 1.4.0"},
      # gun-specific stuff
      {:gun, "~> 1.3"},
      {:idna, "~> 6.0"},
      {:castore, "~> 0.1"},
      {:cowlib, "~> 2.8.0", override: true},
      {:ssl_verify_fun, "~> 1.1"},
      # dialyzer
      {:dialyxir, "~> 1.0", only: [:dev], runtime: false},
    ]
  end
end
