defmodule Heartwood.Bot do

  @spec subscribe(module | {pid | module, keyword}) :: [:ok | {:error, term}]
  def subscribe({name, options}) do
    options = Keyword.put(options, :name, name)

    name
    |> Heartwood.Registry.lookup()
    |> case do
      {_pid, module} -> apply(module, :topic, [options])
      _ -> apply(name, :topic, [options])
    end
    |> List.wrap()
    |> Enum.map(&Heartwood.Channel.subscribe/1)
  end

  def subscribe(module), do: subscribe({module, []})

  @spec subscribe(pid | module, keyword) :: [:ok | {:error, term}]
  def subscribe(name, options), do: subscribe({name, options})
end
