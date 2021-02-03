defmodule Xylem.Supervisor do

  @me __MODULE__

  use DynamicSupervisor

  # API
  def start_link(_), do: DynamicSupervisor.start_link(@me, :ok, name: @me)

  def start_child({name, {mod, cfg}}) when is_list(cfg), do: start_child({mod, Keyword.put(cfg, :name, name)})
  def start_child({mod, cfg}) when is_list(cfg), do: DynamicSupervisor.start_child(@me, {mod, cfg})

  # Supervisor callbacks
  @impl true
  def init(:ok), do: DynamicSupervisor.init(strategy: :one_for_one)
end
