defmodule Xylem.Venue.Alpaca.Socket do
  use Axil

  require Logger

  @conn [host: "api.alpaca.markets", path: "/stream", port: 443]

  def start_link(config) do
    with {:ok, env} <- Keyword.fetch(config, :environment),
         {:ok, %{id: _id, secret: _secret}} <- Keyword.fetch(config, :credentials) do
      state = Enum.into(Keyword.take(config, [:name, :credentials]), %{})
      Axil.start_link(Keyword.merge(@conn, host: host(env)), __MODULE__, state)
    else
      :error -> {:error, :bad_config}
    end
  end

  def handle_upgrade(_conn, %{credentials: %{id: id, secret: secret}} = state) do
    {:send, json_frame(%{action: "authenticate", data: %{key_id: id, secret_key: secret}}), state}
  end

  def handle_receive({type, content}, state) when type in [:text, :binary] do
    content
    |> Jason.decode!()
    |> case do
      %{"stream" => "authorization", "data" => %{"status" => "authorized"}} ->
        {:send, json_frame(%{action: "listen", data: %{streams: ["trade_updates"]}}), state}
      %{"stream" => "authorization", "data" => %{"status" => "unauthorized"}} ->
        Logger.warn "'#{state.name}' Alpaca account unauthorized"
        {:close, state}
      %{"stream" => "listening"} ->
        Logger.debug "listening for '#{state.name}' Alpaca account updates"
        Process.send_after(self(), :restart, :timer.hours(8))
        {:nosend, state}
      %{"stream" => "trade_updates", "data" => data} ->
        {:ok, topic} = Xylem.Venue.Alpaca.topic(Map.to_list(state))
        Xylem.Channel.broadcast(topic, {:venue, normalize(data)})
        {:nosend, state}
      other ->
        Logger.info "inbound message: #{inspect other}"
        {:nosend, state}
    end
  end

  def handle_receive(:close, state) do
    Logger.warn "closing connection to '#{state.name}' Alpaca account"
    {:close, state}
  end

  def handle_other(:restart, state) do
    Logger.debug "restarting WebSocket connection to '#{state.name}' Alpaca account"
    Process.exit(self(), :normal)
    {:nosend, state}
  end

  defp normalize(update) do
    Logger.debug "unnormalized update: #{inspect update}"
    [:id, :timestamp, :type, :side, :symbol, :qty, :price]
    |> Enum.reduce(%{}, &Map.put(&2, &1, normalize(&1, update)))
  end

  defp normalize(:id, %{"order" => %{"client_order_id" => id}}), do: id
  defp normalize(:timestamp, %{"timestamp" => timestamp}), do: timestamp
  defp normalize(:timestamp, %{"order" => %{"updated_at" => timestamp}}), do: timestamp
  defp normalize(:type, %{"event" => "partial_fill"}), do: :partial
  defp normalize(:type, %{"event" => "fill"}), do: :fill
  defp normalize(:type, %{"event" => "new"}), do: :new
  defp normalize(:type, %{"event" => "canceled"}), do: :cancel
  defp normalize(:type, %{"event" => "pending_cancel"}), do: :pending_cancel
  defp normalize(:symbol, %{"order" => %{"symbol" => symbol}}), do: symbol
  defp normalize(:side, %{"order" => %{"side" => side}}), do: String.to_existing_atom(side)
  defp normalize(:qty, %{"qty" => qty}), do: parse_qty(qty)
  defp normalize(:qty, %{"order" => %{"qty" => qty}}), do: parse_qty(qty)
  defp normalize(:price, %{"price" => price}), do: Decimal.new(price)
  defp normalize(:price, %{"order" => %{"limit_price" => price}}) when not is_nil(price), do: Decimal.new(price)
  defp normalize(:price, %{"order" => %{"filled_avg_price" => price}}) when not is_nil(price), do: Decimal.new(price)
  defp normalize(:price, _), do: nil
  defp normalize(_, _), do: nil

  defp parse_qty("-" <> qty), do: parse_qty(qty)
  defp parse_qty(qty), do: String.to_integer(qty)

  defp host("paper"), do: "paper-api.alpaca.markets"
  defp host("live"), do: "api.alpaca.markets"
  defp json_frame(contents), do: {:text, Jason.encode!(contents)}
end
