defmodule Xylem.Bot.Production do

  use GenServer

  alias Xylem.{Bot, Venue, Ledger}

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @impl true
  def init(config), do: Bot.init(config)

  @impl true
  def handle_info({:signal, signals}, state = %{venue: venue, name: name}) do
    IO.inspect(signals, label: "signals")
    positions = Venue.get_positions(venue)
    signals
    |> Ledger.prepare_orders(name, positions)
    |> Enum.map(&Venue.submit_order(venue, &1))
    {:noreply, state}
  end

  def handle_info({:market, data}, config) do
    IO.inspect(data, label: "market data")
    {:noreply, config}
  end

  def handle_info({:venue, update}, state = %{name: name}) do
    IO.inspect(update, label: "venue update")
    Xylem.Logger.record_order_event(name, update, &Venue.event_to_csv/1)
    Ledger.process_event(update)
    {:noreply, state}
  end
end
