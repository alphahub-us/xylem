defmodule Xylem.Orders do
  @moduledoc """
  Abstraction on top of Xylem.Ledger for handling orders: processing order
  updates, generating orders from signals, etc.
  """

  alias Xylem.Ledger

  def process_event(order_evt) do
    case extract_bot(order_evt) do
      {:ok, bot} -> Ledger.update(bot, order_evt)
      _ -> :ok
    end
  end

  @doc """
  Prepares a batch of orders based on available positions and incoming signals.
  """
  def prepare(signals, bot, positions) when is_list(signals) do
    signals
    |> Enum.map(&prepare(&1, bot, positions))
    |> List.flatten()
  end

  def prepare(signal, bot, positions) do
    signal
    |> add_quantity(bot, positions)
    |> List.wrap()
    |> remove_invalid_orders()
    |> add_ids(bot)
    |> Enum.map(&Map.take(&1, [:symbol, :qty, :price, :side, :id]))
    |> maybe_breakup()
  end

  def generate_id(bot), do: generate_id(bot, generate_group())

  def generate_id(bot, group) do
    id = hd Enum.reverse(String.split(UUID.uuid4(), "-"))
    Enum.join(["xylem", bot, group, id], "-")
  end

  @doc """
  Calculates the remaining quantity needed to fill an order
  """
  def get_remaining_qty(order = %{symbol: symbol, qty: qty, side: side}) do
    with {:ok, bot} <- extract_bot(order),
         {:ok, {_, current}} <- Ledger.get_open_position(bot, symbol, side: side) do
      qty - abs(current)
    else
      {:error, _} -> 0
    end
  end

  defp generate_group(), do: hd tl String.split(UUID.uuid4(), "-")

  defp extract_bot(%{id: "xylem-" <> rest}) do
    {:ok, rest |> String.split("-") |> hd()}
  end
  defp extract_bot(_), do: {:error, :no_bot}

  defp add_quantity(signal, bot, positions) do
    find_qty(signal, bot, positions)
    |> List.wrap()
    |> Enum.map(&Map.put(signal, :qty, &1))
  end

  defp find_qty(%{type: :close, symbol: symbol, side: side}, bot, positions) do
    with {:ok, {_, recorded}} <- Ledger.get_open_position(bot, symbol),
         [%{qty: available}] <- Enum.filter(positions, & &1[:symbol] == symbol) do
      [recorded, available] = Enum.map([recorded, available], fn n -> if side == :sell, do: n, else: -n end)
      [min(recorded, available), recorded - max(0, available)]
    else
      _ -> 0
    end
  end

  defp find_qty(signal = %{type: :open}, bot, _positions) do
    case Ledger.get_funds(bot) do
      {:ok, funds} -> qty_from_funds(funds, signal.price, signal.weight)
      _ -> 0
    end
  end

  defp qty_from_funds(funds, price, weight) do
    funds
    |> Decimal.div(price)
    |> Decimal.mult(weight)
    |> Decimal.round(0, :floor)
    |> Decimal.to_integer()
  end

  defp add_ids(orders, bot) do
    group = generate_group()
    Enum.map(orders, &Map.put(&1, :id, generate_id(bot, group)))
  end

  defp remove_invalid_orders(orders), do: Enum.filter(orders, & &1[:qty] > 0)

  defp maybe_breakup(signal), do: signal
end
