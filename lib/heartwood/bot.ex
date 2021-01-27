defmodule Heartwood.Bot do

  @spec subscribe(module | {pid | module, keyword}) :: [:ok | {:error, term}]
  def subscribe({name, options}) do
    options = Keyword.put(options, :name, name)

    name
    |> Heartwood.Registry.lookup()
    |> case do
      {pid, module} -> apply(module, :topic, [pid, options])
      _ -> apply(name, :topic, [options])
    end
    |> List.wrap()
    |> Enum.map(&Heartwood.Channel.subscribe/1)
  end

  def subscribe(module), do: subscribe({module, []})
end
