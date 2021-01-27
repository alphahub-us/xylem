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
      mod: {Heartwood.Application, []}
    ]
  end

  defp deps do
    [
      {:phoenix_pubsub, "~> 2.0"},
      {:axil, git: "https://git.sr.ht/~dcrck/axil"},
      {:jason, ">= 1.0.0"},
      # Base client
      {:tesla, "~> 1.4.0"},
      # gun-specific stuff
      {:gun, "~> 1.3"},
      {:idna, "~> 6.0"},
      {:castore, "~> 0.1"},
      {:cowlib, "~> 2.8.0", override: true},
      {:ssl_verify_fun, "~> 1.1"},
    ]
  end
end
