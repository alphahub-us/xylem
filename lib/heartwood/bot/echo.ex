defmodule Heartwood.Bot.Echo do

  use GenServer

  alias Heartwood.Bot

  def start_link(config) do
    GenServer.start_link(__MODULE__, config)
  end

  @impl true
  def init(config) do
    config
    |> Keyword.take([:market, :venue, :source])
    |> Keyword.values()
    |> Enum.each(&Bot.subscribe/1)

    {:ok, config}
  end

  @impl true
  def handle_info({:source, signals}, config) do
    IO.inspect(signals, label: "signals")
    {:noreply, config}
  end

  def handle_info({:market, data}, config) do
    IO.inspect(data, label: "market data")
    {:noreply, config}
  end

  def handle_info({:venue, update}, config) do
    IO.inspect(update, label: "venue update")
    {:noreply, config}
  end
end
