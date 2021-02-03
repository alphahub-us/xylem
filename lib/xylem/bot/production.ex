defmodule Xylem.Bot.Production do

  use GenServer

  alias Xylem.{Bot, Venue, Ledger}

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @impl true
  def init(config), do: Bot.init(config)

  @impl true
  def handle_info({:signal, signals}, state = %{venue: venue, name: name}) do
    IO.inspect(signals, label: "[#{name}] signals")
    positions = Venue.get_positions(venue)
    signals
    |> Ledger.prepare_orders(name, positions)
    |> IO.inspect(label: "orders")
    |> Enum.map(&Venue.submit_order(venue, &1, type: :limit))
    {:noreply, state}
  end

  def handle_info({:data, data}, state = %{name: name}) do
    IO.inspect(data, label: "[#{name}] market data")
    {:noreply, state}
  end

  def handle_info({:venue, update}, state = %{name: name}) do
    IO.inspect(update, label: "[#{name}] venue update")
    Xylem.Logger.record_order_event(name, update, &Venue.event_to_csv/1)
    Ledger.process_event(update)
    {:noreply, state}
  end
end
