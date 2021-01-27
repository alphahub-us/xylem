defmodule Heartwood.Loader do

  use Task

  def start_link(config) do
    Task.start_link(__MODULE__, :run, [config])
  end

  def run(config) do
    [:venues, :sources, :markets, :bots]
    |> Enum.map(&Keyword.get(config, &1, []))
    |> List.flatten()
    |> Enum.filter(&needs_startup?/1)
    |> Enum.each(&Heartwood.Supervisor.start_child/1)
  end

  defp needs_startup?({_name, {module, _opts}}), do: needs_startup?(module)
  defp needs_startup?({module, _opts}), do: needs_startup?(module)
  defp needs_startup?(module), do: is_integer(module.__info__(:functions)[:start_link])
end
