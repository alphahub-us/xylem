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
      {:phoenix_pubsub, "~> 2.0"}
    ]
  end
end
