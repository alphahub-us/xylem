defmodule Xylem.Bot do

  require Logger

  @spec subscribe(module | {pid | module, keyword}) :: [:ok | {:error, term}]
  def subscribe({name, options}) do
    options = Keyword.put(options, :name, name)

    with {_pid, module} <- Xylem.Registry.lookup(name),
         {:ok, channels} <- apply(module, :topic, [options]) do
      channels
      |> List.wrap()
      |> Enum.map(&Xylem.Channel.subscribe/1)
    else
      _other ->  Logger.debug "unable to subscribe to #{inspect name}"
    end
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
    |> Keyword.take([:venue, :signal, :data])
    |> Keyword.values()
    |> Enum.each(&subscribe/1)

    with {:ok, name} <- Keyword.fetch(config, :name) do
      Xylem.Logger.start(Keyword.merge([log_path: "/tmp/#{name}.log"], config))
    end

    {:ok, Enum.into(config, %{})}
  end
end
