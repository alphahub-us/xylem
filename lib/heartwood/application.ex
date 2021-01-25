defmodule Heartwood.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Heartwood.Channel,
    ]

    opts = [strategy: :one_for_one, name: Heartwood.Supervisor]
    Supervisor.start_link(children, opts)
  end
end
