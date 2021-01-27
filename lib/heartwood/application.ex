defmodule Heartwood.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, _args) do
    children = [
      Heartwood.Registry,
      Heartwood.Channel,
      Heartwood.Supervisor,
      {Heartwood.Loader, modules()}
    ]

    opts = [strategy: :rest_for_one, name: Heartwood.Application]
    Supervisor.start_link(children, opts)
  end

  def modules() do
    Application.get_all_env(:heartwood)
  end
end
