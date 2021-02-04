defmodule Xylem.Data.Polygon do
  use Axil

  @me __MODULE__

  @behaviour Xylem.Data

  @impl Xylem.Data
  def topic(%{type: type, symbol: symbol}), do: {:ok, get_topic(type, symbol)}
  def topic(symbol) when is_binary(symbol), do: topic(%{type: "A", symbol: symbol})
  def topic(_), do: {:ok, []}

  def start_link(config) do
    with {:ok, %{api_key: key}} <- Keyword.fetch(config, :credentials) do
      conn = [
        host: from_endpoint(Keyword.get(config, :endpoint, :realtime)),
        path: from_cluster(Keyword.get(config, :cluster, :stocks)),
        port: 443
      ]
      Axil.start_link(conn, @me, %{"key" => key, "ready" => false}, name: get_name(config))
    else
      :error -> {:error, :no_key}
    end
  end

  defp get_name(config) do
    case Keyword.fetch(config, :name) do
      {:ok, name} -> {:via, Registry, {Xylem.Registry, name, @me}}
      :error -> @me
    end
  end

  defp from_endpoint(:delayed), do: "delayed.polygon.io"
  defp from_endpoint(:realtime), do: "socket.polygon.io"

  defp from_cluster(:stocks), do: "/stocks"
  defp from_cluster(:forex), do: "/forex"
  defp from_cluster(:crypto), do: "/crypto"

  # Axil overrides
  def handle_send(message, state) do
    {:send, json_frame(message), state}
  end

  def handle_receive({:text, content}, state) do
    content
    |> Jason.decode!()
    |> case do
      [%{"ev" => "status", "status" => "connected"}] ->
        {:send, json_frame(%{action: "auth", params: state["key"]}), Map.delete(state, "key")}
      [%{"ev" => "status", "status" => "auth_success"}] when map_size(state) > 1 ->
        {:send, subscribe_frame(Map.keys(state) -- ["ready"]), %{state | "ready" => true}}
      [%{"ev" => "status", "status" => "auth_success"}] ->
        {:nosend, %{state | "ready" => true}}
      [%{"ev" => "status", "status" => "success"}] ->
        {:nosend, state}
      list = [%{"ev" => event, "sym" => symbol} | _rest] ->
        Xylem.Channel.broadcast(get_topic(event, symbol), {:data, list})
        {:nosend, state}
      other ->
        IO.inspect(other, label: "inbound message")
        {:nosend, state}
    end
  end

  def handle_receive(:close, state), do: {:close, state}

  # work through all the tickers, incrementing the counts and keeping track of
  # new subscriptions. Then subscribe to all new tickers.
  def handle_other({:subscribe, tickers}, state) when is_list(tickers) do
    tickers
    |> Enum.reduce({[], state}, fn ticker, {new_subs, new_state} ->
      case increment_ticker_count(new_state, ticker) do
        {nil, %{"ready" => true} = new_state} -> {[ticker | new_subs], new_state}
        {_value, new_state} -> {new_subs, new_state}
      end
    end)
    |> case do
      {[], new_state} -> {:nosend, new_state}
      {tickers, new_state} -> {:send, subscribe_frame(tickers), new_state}
    end
  end

  def handle_other({:subscribe, ticker}, state) do
    case increment_ticker_count(state, ticker) do
      {nil, %{"ready" => true} = new_state} -> {:send, subscribe_frame(ticker), new_state}
      {_value, new_state} -> {:nosend, new_state}
    end
  end

  def handle_other({:unsubscribe, ticker}, state) do
    case decrement_ticker_count(state, ticker) do
      {1, new_state} -> {:send, unsubscribe_frame(ticker), new_state}
      {_value, new_state} -> {:nosend, new_state}
    end
  end

  defp increment_ticker_count(state, ticker) do
    Map.get_and_update(state, ticker, fn
      nil -> {nil, 1}
      value -> {value, value + 1}
    end)
  end

  defp decrement_ticker_count(state, ticker) do
    Map.get_and_update(state, ticker, fn
      1 -> :pop
      nil -> :pop
      value -> {value, value - 1}
    end)
  end

  defp get_topic(type, symbol), do: "polygon:#{type}:#{symbol}"

  defp subscribe_frame(tickers) when is_list(tickers), do: json_frame(%{action: "subscribe", params: Enum.join(tickers, ",")})
  defp subscribe_frame(ticker), do: json_frame(%{action: "subscribe", params: ticker})
  defp unsubscribe_frame(ticker), do: json_frame(%{action: "unsubscribe", params: ticker})

  defp json_frame(contents), do: {:text, Jason.encode!(contents)}
end
