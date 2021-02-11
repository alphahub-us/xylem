defmodule Xylem.Ledger do
  @db __MODULE__

  import NaiveDateTime, only: [diff: 3, add: 3, utc_now: 0, compare: 2]

  def child_spec(opts), do: %{id: @db, start: {@db, :start_link, [opts]}}

  def start_link(options) do
    [data_dir: "/tmp/xylem", name: @db]
    |> Keyword.merge(options)
    |> CubDB.start_link()
  end

  @doc """
  Provides a summary for a bot's history, sorted by newest event first.
  """
  @spec history(String.t) :: [tuple]
  def history(bot), do: history(bot, :positions)

  @spec history(String.t, :positions | :funds) :: [tuple]
  def history(bot, :positions) do
    prettify = fn {{_,_,symbol,ts}, v} -> {from_epoch(ts), symbol, v} end
    {:ok, positions} = CubDB.select(@db, Keyword.merge(position_opts(bot), reverse: true, pipe: [map: prettify]))
    Enum.sort(positions, fn {ts1, _, _}, {ts2, _, _} -> compare(ts1, ts2) in [:gt, :eq] end)
  end

  def history(bot, :funds) do
    prettify = fn {{_, _, ts}, funds} -> {from_epoch(ts), from_cents(funds)} end
    {:ok, funds} = CubDB.select(@db, Keyword.merge(fund_opts(bot), reverse: true, pipe: [map: prettify]))
    funds
  end

  def history(_bot, _), do: []

  @doc """
  Gets the bot's current open position for a symbol as a two-element tuple
  representing `{gain, shares}`.
  """
  def get_open_position(bot, symbol, opts \\ []) do
    case last_open_position(bot, symbol) do
      {:ok, _, position} -> {:ok, accumulate_side(position, Keyword.get(opts, :side))}
      error -> error
    end
  end

  @doc """
  Gets the bot's last position for a symbol as a two-element tuple representing
  `{gain, shares}`.
  """
  def get_position(bot, symbol, opts \\ []) do
    case last_position(bot, symbol) do
      {:ok, {_, position}} -> {:ok, accumulate_side(position, Keyword.get(opts, :side))}
      error -> error
    end
  end

  @doc """
  sets the funds available for a bot.
  """
  def set_funds(bot, funds) when is_float(funds) or is_integer(funds) do
    CubDB.put(@db, {:funds, bot, epoch()}, to_cents(funds))
  end

  def set_funds(bot, funds), do: set_funds(bot, Decimal.to_float(funds))

  @doc """
  Gets the funds available for a bot.
  """
  def get_funds(bot) do
    case CubDB.select(@db, Keyword.merge(fund_opts(bot), reverse: true, pipe: [take: 1])) do
      {:ok, [{_, funds}]} -> {:ok, from_cents(funds)}
      _ -> {:error, :no_funds}
    end
  end

  @doc """
  record an update in the Ledger
  """
  def update(bot, details = %{symbol: symbol, type: type}) do
    case last_open_position(bot, symbol) do
      {:error, :no_open_position} when type == :new -> create_position(bot, symbol)
      {:ok, key, []} when type == :cancel -> CubDB.delete(@db, key)
      {:ok, key, pos} when type in [:partial, :fill] ->
        new_pos = update_positions(pos, details)
        CubDB.put(@db, key, new_pos)
        apply_gain(bot, new_pos)
      _ -> :ok
    end
  end

  def update(_, _), do: :ok

  defp create_position(bot, sym), do: CubDB.put_new(@db, {:positions, bot, sym, epoch()}, [])

  defp accumulate_side(updates, :buy) do
    updates |> Enum.filter(&elem(&1, 1) > 0) |> accumulate()
  end

  defp accumulate_side(updates, :sell) do
    updates |> Enum.filter(&elem(&1, 1) < 0) |> accumulate()
  end

  defp accumulate_side(updates, _), do: updates |> accumulate()

  defp accumulate(updates) do
    Enum.reduce(updates, {to_decimal(0), 0}, fn {price, qty}, {gain, shares} ->
      {Decimal.sub(gain, Decimal.mult(qty, price)), shares + qty}
    end)
  end

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

  defp last_position(bot, symbol) do
    case CubDB.select(@db, Keyword.merge(position_opts(bot, symbol), reverse: true, pipe: [take: 1])) do
      {:ok, [result]} -> {:ok, result}
      _ -> {:error, :no_position}
    end
  end

  defp update_positions(current, update = %{side: :sell}) do
    update_positions(current, Map.delete(%{update | qty: update.qty * -1}, :side))
  end

  defp update_positions(current, update = %{side: :buy}) do
    update_positions(current, Map.delete(update, :side))
  end

  defp update_positions(updates, %{qty: qty, price: price}), do: [{to_decimal(price), qty} | updates]

  defp to_decimal(price) when is_integer(price), do: Decimal.new(price)
  defp to_decimal(price) when is_float(price), do: Decimal.from_float(price)
  defp to_decimal(price), do: price

  defp fund_opts(bot), do: [min_key: {:funds, bot, 0}, max_key: {:funds, bot, nil}]

  defp position_opts(bot), do: [min_key: {:positions, bot, "", 0}, max_key: {:positions, bot, "~", nil}]
  defp position_opts(bot, sym), do: [min_key: {:positions, bot, sym, 0}, max_key: {:positions, bot, sym, nil}]
end
