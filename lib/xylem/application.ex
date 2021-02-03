defmodule Xylem.Application do
  @moduledoc false

  use Application

  @impl true
  def start(_type, args) do
    children = [
      Xylem.Registry,
      Xylem.Channel,
      Xylem.Supervisor,
      {Xylem.Loader, modules()},
      ledger(args),
    ]
    |> List.flatten()

    opts = [strategy: :rest_for_one, name: Xylem.Application]
    Supervisor.start_link(children, opts)
  end

  def ledger(env: :test), do: []
  def ledger(_), do: [{Xylem.Ledger, Application.get_env(:xylem, :ledger, [])}]

  def modules() do
    Application.get_all_env(:xylem)
  end
end
