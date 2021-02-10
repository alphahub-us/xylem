defmodule Xylem.Ledger do
  @db __MODULE__

  import NaiveDateTime, only: [diff: 3, add: 3, utc_now: 0, compare: 2]

  def child_spec(opts) do
    %{id: @db, start: {@db, :start_link, [opts]}}
  end

  def start_link(options) do
    [data_dir: "/tmp/xylem", name: @db]
    |> Keyword.merge(options)
    |> CubDB.start_link()
  end

  def history(bot, type \\ :positions) do
    case type do
      :positions ->
        {:ok, positions} = CubDB.select(
          @db,
          min_key: {type, bot, "", 0},
          max_key: {type, bot, "ZZZZ", nil},
          reverse: true,
          pipe: [map: fn {{_,_,symbol,ts}, v} -> {from_epoch(ts), symbol, v} end]
        )
        positions
        |> Enum.sort(fn {ts1, _, _}, {ts2, _, _} -> compare(ts1, ts2) in [:gt, :eq] end)
      :funds ->
        {:ok, funds} = CubDB.select(
          @db,
          min_key: {type, bot, 0},
          max_key: {type, bot, nil},
          reverse: true,
          pipe: [map: fn {{_, _, ts}, v} -> {from_epoch(ts), v} end]
        )
        funds
      _ -> []
    end
  end

  @doc """
  Processes inbound order events
  """
  @spec process_event(Xylem.Venue.order_event) :: :ok
  def process_event(event) do
    with {:ok, bot} <- extract_bot_from_event(event),
         {:ok, type} <- Map.fetch(event, :type),
         {:ok, symbol} <- Map.fetch(event, :symbol) do
      case last_open_position(bot, symbol) do
        {:error, :no_open_position} when type == :new ->
          CubDB.put_new(@db, {:positions, bot, symbol, epoch()}, [])
        {:ok, key, []} when type == :cancel ->
          CubDB.delete(@db, key)
        {:ok, key, positions} when type in [:partial, :fill] ->
          new_positions = update_positions(positions, event)
          CubDB.put(@db, key, new_positions)
          apply_gain(bot, new_positions)
        _ -> :ok
      end
    else
      _ -> :ok
    end
  end

  @doc """
  Calculates the net gain and remaining shares for a position.
  """
  def accumulate(updates) do
    Enum.reduce(updates, {to_decimal(0), 0}, fn {price, qty}, {gain, shares} ->
      {Decimal.sub(gain, Decimal.mult(qty, price)), shares + qty}
    end)
  end

  @doc """
  Retrieves the last position on a symbol
  """
  def last_position(bot, symbol) do
    CubDB.select(@db,
      reverse: true,
      min_key: {:positions, bot, symbol, 0},
      max_key: {:positions, bot, symbol, nil},
      pipe: [take: 1]
    )
    |> case do
      {:ok, [result]} -> {:ok, result}
      _ -> {:error, :no_position}
    end
  end

  @doc """
  Prepares a batch of orders based on available positions and incoming signals.
  """
  def prepare_orders(signals, bot, positions) when is_list(signals) do
    signals
    |> Enum.map(&prepare_orders(&1, bot, positions))
    |> List.flatten()
  end

  def prepare_orders(signal, bot, positions) do
    signal
    |> add_quantity(bot, positions)
    |> List.wrap()
    |> remove_invalid_orders()
    |> add_ids(bot)
    |> Enum.map(&Map.take(&1, [:symbol, :qty, :price, :side, :id]))
    |> maybe_breakup()
  end

  @doc """
  sets the funds available for a bot.
  """
  def set_funds(bot, funds) when is_float(funds) or is_integer(funds) do
    CubDB.put(@db, {:funds, bot, epoch()}, to_cents(funds))
  end

  def set_funds(bot, funds) do
    set_funds(bot, Decimal.to_float(funds))
  end

  @doc """
  Gets the funds available for a bot.
  """
  def get_funds(bot) do
    CubDB.select(@db,
      reverse: true,
      min_key: {:funds, bot, 0},
      max_key: {:funds, bot, nil},
      pipe: [take: 1]
    )
    |> case do
      {:ok, [{_, funds}]} -> {:ok, from_cents(funds)}
      _ -> {:error, :no_funds}
    end
  end

  def generate_id(bot), do: generate_id(bot, generate_group())

  def generate_id(bot, group) do
    id = hd Enum.reverse(String.split(UUID.uuid4(), "-"))
    Enum.join(["xylem", bot, group, id], "-")
  end

  defp generate_group(), do: hd tl String.split(UUID.uuid4(), "-")

  defp apply_gain(bot, positions) do
    with {:ok, funds} <- get_funds(bot),
         {gain, 0} <- accumulate(positions) do
      set_funds(bot, Decimal.add(funds, gain))
    else
      _ -> :ok
    end
  end

  defp to_cents(funds), do: round(Float.round(funds, 2) * 100)
  defp from_cents(funds), do: Decimal.div(to_decimal(funds), 100)

  defp add_ids(orders, bot) do
    group = generate_group()
    Enum.map(orders, &Map.put(&1, :id, generate_id(bot, group)))
  end

  defp add_quantity(signal = %{type: :close, symbol: symbol}, bot, positions) do
    with {:ok, _key, position} = last_open_position(bot, symbol),
         {_, qty} = accumulate(position),
         [%{qty: available}] <- Enum.filter(positions, & &1[:symbol] == symbol) do
      sign = if signal.side == :sell, do: 1, else: -1
      qty = sign * qty
      available = sign * available
      [Map.put(signal, :qty, min(qty, available)), Map.put(signal, :qty, qty - max(0, available))]
    else
      _ -> Map.put(signal, :qty, 0)
    end
  end

  defp add_quantity(signal = %{type: :open}, bot, _positions) do
    with {:ok, funds} <- get_funds(bot) do
      Map.put(signal, :qty, qty_from_funds(funds, signal.price, signal.weight))
    else
      _ -> Map.put(signal, :qty, 0)
    end
  end

  defp qty_from_funds(funds, price, weight) do
    funds
    |> Decimal.div(price)
    |> Decimal.mult(weight)
    |> Decimal.round(0, :floor)
    |> Decimal.to_integer()
  end

  defp remove_invalid_orders(orders) do
    Enum.filter(orders, & &1[:qty] > 0)
  end

  defp maybe_breakup(signal), do: signal

  defp extract_bot_from_event(%{id: "xylem-" <> rest}) do
    {:ok, rest |> String.split("-") |> hd()}
  end
  defp extract_bot_from_event(_), do: {:error, :no_bot}

  defp epoch(), do: diff(utc_now(), ~N[1970-01-01 00:00:00], :millisecond)
  defp from_epoch(ts), do: add(~N[1970-01-01 00:00:00], ts, :millisecond)

  defp last_open_position(bot, symbol) do
    with {:ok, {key, position}} <- last_position(bot, symbol),
         {_, qty} when qty != 0 or position == [] <- accumulate(position) do
      {:ok, key, position}
    else
      _ -> {:error, :no_open_position}
    end
  end

  defp update_positions(current, update = %{side: :sell}) do
    update_positions(current, Map.delete(%{update | qty: update.qty * -1}, :side))
  end

  defp update_positions(current, update = %{side: :buy}) do
    update_positions(current, Map.delete(update, :side))
  end

  defp update_positions([], %{qty: qty, price: price}) do
    [{to_decimal(price), qty}]
  end

  defp update_positions(updates, %{qty: qty, price: price}) do
    [{to_decimal(price), qty} | updates]
  end

  defp to_decimal(price) when is_integer(price), do: Decimal.new(price)
  defp to_decimal(price) when is_float(price), do: Decimal.from_float(price)
  defp to_decimal(price), do: price
end
