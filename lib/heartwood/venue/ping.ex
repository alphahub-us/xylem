defmodule Heartwood.Venue.Ping do

  use GenServer

  @behaviour Heartwood.Venue

  @impl Heartwood.Venue
  def topic(name: name) do
    "venue:#{name}"
  end

  def start_link(options) do
    GenServer.start_link(__MODULE__, Enum.into(options, %{delay: 10}))
  end

  @impl true
  def init(config = %{name: name}) do
    Heartwood.Registry.register(name, __MODULE__)
    schedule_ping(config)
    {:ok, config}
  end

  @impl true
  def handle_info(:ping, state = %{name: name}) do
    Heartwood.Channel.broadcast("venue:#{name}", {:venue, "ping"})
    schedule_ping(state)
    {:noreply, state}
  end

  defp schedule_ping(%{delay: delay}) do
    Process.send_after(self(), :ping, delay * 1000)
  end
end
