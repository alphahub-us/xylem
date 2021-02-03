defmodule Xylem.Bot do

  @spec subscribe(module | {pid | module, keyword}) :: [:ok | {:error, term}]
  def subscribe({name, options}) do
    options = Keyword.put(options, :name, name)

    name
    |> Xylem.Registry.lookup()
    |> case do
      {_pid, module} -> apply(module, :topic, [options])
      _ -> apply(name, :topic, [options])
    end
    |> List.wrap()
    |> Enum.map(&Xylem.Channel.subscribe/1)
  end

  def subscribe(module), do: subscribe({module, []})

  @spec subscribe(pid | module, keyword) :: [:ok | {:error, term}]
  def subscribe(name, options), do: subscribe({name, options})

  @doc """
  Generic bot initialization function. Subscribes to venue, market, source;
  initializes Logger
  """
  @spec init(keyword) :: {:ok, term}
  def init(config) do
    config
    |> Keyword.take([:market, :venue, :source])
    |> Keyword.values()
    |> Enum.each(&subscribe/1)

    with {:ok, name} <- Keyword.fetch(config, :name) do
      Xylem.Logger.start(Keyword.merge([log_path: "/tmp/#{name}.log"], config))
    end

    {:ok, Enum.into(config, %{})}
  end
end
