defmodule Heartwood.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    children = [
      Heartwood.Registry,
      Heartwood.Channel,
      Heartwood.Supervisor,
      {Heartwood.Loader, modules()},
      ledger(args),
    ]
    |> List.flatten()

    opts = [strategy: :rest_for_one, name: Heartwood.Application]
    Supervisor.start_link(children, opts)
  end

  def ledger(env: :test), do: []
  def ledger(_), do: [{Heartwood.Ledger, Application.get_env(:heartwood, :ledger, [])}]

  def modules() do
    Application.get_all_env(:heartwood)
  end
end
