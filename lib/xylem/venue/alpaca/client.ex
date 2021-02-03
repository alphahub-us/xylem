defmodule Xylem.Venue.Alpaca.Client do
  use Agent

  def start_link(config) do
    Agent.start_link(fn -> Alpaca.client(config) end)
  end

  def get_positions(client) do
    case Agent.get(client, &Alpaca.Positions.list/1) do
      {:ok, positions} ->
        Enum.map(positions, fn %{"qty" => qty, "symbol" => symbol} ->
          %{qty: String.to_integer(qty), symbol: symbol}
        end)
      error -> error
    end
  end

  def submit_order(client, order, options) do
    Agent.get(client, &Alpaca.Orders.create(&1, to_params(order, Keyword.get(options, :type, :market))))
  end

  def cancel_order(client, order, _) do
    case Agent.get(client, &Alpaca.Orders.retrieve_by_client_order_id(&1, order.id)) do
      {:ok, order} -> Agent.get(client, &Alpaca.Orders.delete(&1, order["id"]))
      _ -> :ok
    end
  end

  defp to_params(order, type) do
    order
    |> Map.take([:symbol, :qty, :side])
    |> Enum.map(fn
      {:side, side} when is_atom(side) -> {:side, Atom.to_string(side)}
      other -> other
    end)
    |> Enum.into(%{time_in_force: "day", client_order_id: order.id})
    |> Enum.into(type_params(order, type))
  end

  defp type_params(_, :market), do: %{type: "market"}
  defp type_params(%{price: price}, :limit), do: %{type: "limit", limit_price: Decimal.to_float(price)}
end
