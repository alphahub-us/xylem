defmodule Xylem.Bot.Production do

  use GenServer

  alias Xylem.{Bot, Venue, Orders, Conditions, Data}
  alias Decimal, as: D

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @impl true
  def init(config), do: Bot.init(config)

  @impl true
  def handle_info({:signal, signals}, state = %{venue: venue, name: name}) do
    IO.inspect(signals, label: "[#{name}] signals")
    positions = Venue.get_positions(venue)
    orders = Orders.prepare(signals, name, positions) |> IO.inspect(label: "[#{name}] orders")
    Enum.each(orders, fn order ->
      Conditions.add(order, {condition_for(order), {:cancel, order}}, 60_000)
      Venue.submit_order(venue, order, type: :limit)
    end)

    {:noreply, state}
  end

  def handle_info({:data, data}, state = %{name: name}) do
    IO.inspect(data, label: "[#{name}] market data")
    Enum.each(data, &check_off(&1, state))
    {:noreply, state}
  end

  def handle_info({:venue, update = %{symbol: symbol}}, state = %{name: name, data: data}) do
    IO.inspect(update, label: "[#{name}] venue update")
    with {:ok, type} when type in [:fill, :cancel] <- Map.fetch(update, :type),
         ref when not is_reference(ref) <- Conditions.remove(update),
         {:ok, topic} <- Data.topic(data, symbol) do
      Data.unsubscribe(data, topic)
    end
    Xylem.Logger.record_order_event(name, update, &Venue.event_to_csv/1)
    Orders.process_event(update)
    {:noreply, state}
  end

  def handle_info({:condition_added, %{symbol: symbol}, _condition}, state = %{data: data}) do
    with {:ok, topic} <- Data.topic(data, symbol) do
      Data.subscribe(data, topic)
    end
    {:noreply, state}
  end

  defp check_off(%{symbol: symbol, price: price}, state = %{name: name}) do
    case Conditions.check_off(name, {:price, symbol, price}) do
      {:ok, list} -> Enum.each(list, &cancel_and_replace(&1, state))
      _ -> :ok
    end
  end

  defp cancel_and_replace({_id, {:cancel, order}}, %{name: name, venue: venue}) do
    new_order = %{order | id: Orders.generate_id(name), qty: Orders.get_remaining_qty(order)}
    Venue.cancel_order(venue, order)
    Venue.submit_order(venue, new_order, type: :market)
  end
  defp cancel_and_replace(_, _), do: :ok

  defp condition_for(%{side: :buy, price: price}), do: {:gt, D.mult(price, D.new("1.0033"))}
  defp condition_for(%{side: :sell, price: price}), do: {:lt, D.mult(price, D.new("0.9967"))}
end
