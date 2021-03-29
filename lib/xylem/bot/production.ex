defmodule Xylem.Bot.Production do

  use GenServer

  alias Xylem.{Bot, Venue, Orders, Conditions, Data}
  alias Decimal, as: D

  def start_link(config), do: GenServer.start_link(__MODULE__, config)

  @impl true
  def init(config) do
    {:ok, cfg} = Bot.init(config)
    {:ok, %{config: cfg, queue: %{}}}
  end

  @impl true
  def handle_info({:signal, signals}, state) do
    %{venue: venue, name: name} = Map.take(state.config, [:venue, :name])
    IO.inspect(signals, label: "[#{name}] signals")
    positions = Venue.get_positions(venue)
    orders = Orders.prepare(signals, name, positions) |> IO.inspect(label: "[#{name}] orders")

    {:noreply, enqueue_orders(orders, state)}
  end

  def handle_info({:data, data}, state = %{config: %{name: name}}) do
    IO.inspect(data, label: "[#{name}] market data")
    Enum.each(List.wrap(data), &check_off(&1, state))
    {:noreply, state}
  end

  def handle_info({:venue, update = %{symbol: symbol}}, state) do
    %{name: name, data: data} = Map.take(state.config, [:name, :data])
    IO.inspect(update, label: "[#{name}] venue update")
    with {:ok, type} when type in [:fill, :cancel] <- Map.fetch(update, :type),
         ref when not is_reference(ref) <- Conditions.remove(update),
         {:ok, topic} <- Data.topic(data, symbol) do
      Data.unsubscribe(data, topic)
    end
    Xylem.Logger.record_order_event(name, update, &Venue.event_to_csv/1)
    Orders.process_event(update)
    {:noreply, handle_event(update, state)}
  end

  def handle_info({:condition_added, %{symbol: symbol}, _}, state = %{config: %{data: data}}) do
    with {:ok, topic} <- Data.topic(data, symbol) do
      Data.subscribe(data, topic)
    end
    {:noreply, state}
  end

  def handle_info({:submit_market, order, qty}, state) do
    %{name: name, venue: venue} = Map.take(state.config, [:name, :venue])
    new_order = %{order | id: Orders.generate_id(name), qty: qty} |> IO.inspect(label: "market order")
    Venue.submit_order(venue, new_order, type: :market) |> IO.inspect(label: "market order submission")
    state = case pop_in(state, [:queue, order.id]) do
      {nil, state} -> state
      {orders, state} -> put_in(state, [:queue, new_order.id], orders)
    end
    {:noreply, state}
  end

  defp handle_event(%{type: :fill, id: id}, state) do
    case pop_in(state, [:queue, id]) do
      {nil, state} -> state
      {other_orders, state} -> enqueue_orders(other_orders, state)
    end
  end

  defp handle_event(_, state), do: state

  defp enqueue_orders(orders, state = %{config: %{venue: venue}}) do
    orders
    |> Enum.group_by(&{Map.get(&1, :symbol), Map.get(&1, :side)})
    |> Map.values()
    |> Enum.reduce(state, fn [order | rest], state ->
      Conditions.add(order, {condition_for(order), {:cancel, order}}, 60_000)
      Venue.submit_order(venue, order, type: :limit)
      if rest != [], do: put_in(state, [:queue, order.id], rest), else: state
    end)
  end

  defp check_off(%{symbol: symbol, price: price}, state = %{config: %{name: name}}) do
    with {:ok, list} <- Conditions.check_off(name, {:price, symbol, price}) do
      Enum.each(list, &cancel_and_replace(&1, state))
    end
  end

  defp cancel_and_replace({_id, {:cancel, order}}, %{config: %{venue: venue}}) do
    qty = Orders.get_remaining_qty(order)
    Venue.cancel_order(venue, order)
    Process.send_after(self(), {:submit_market, order, qty}, 5_000)
  end

  defp cancel_and_replace(_, _), do: :ok

  defp condition_for(%{side: :buy, price: price}), do: {:gt, D.mult(price, D.new("1.0033"))}
  defp condition_for(%{side: :sell, price: price}), do: {:lt, D.mult(price, D.new("0.9967"))}
end
