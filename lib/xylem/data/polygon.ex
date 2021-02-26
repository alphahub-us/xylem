defmodule Xylem.Data.Polygon do
  use Axil

  require Logger

  alias Decimal, as: D
  @me __MODULE__

  @behaviour Xylem.Data

  @impl Xylem.Data
  def topic(symbol) when is_binary(symbol), do: topic(%{type: "A", symbol: symbol})
  def topic(%{type: type, symbol: symbol}), do: {:ok, to_topic(get_ticker(type, symbol))}
  def topic(_), do: {:ok, []}

  @impl Xylem.Data
  def subscribe(pid, topic) do
    Xylem.Channel.subscribe(topic)
    Logger.debug "subscribing to #{topic} (#{to_ticker(topic)})"
    send(pid, {:subscribe, to_ticker(topic)})
  end

  @impl Xylem.Data
  def unsubscribe(pid, topic) do
    Xylem.Channel.unsubscribe(topic)
    Logger.debug "unsubscribing from #{topic} (#{to_ticker(topic)})"
    send(pid, {:unsubscribe, to_ticker(topic)})
  end

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
        tickers = Map.keys(state) -- ["ready"]
        Logger.debug "Polygon successfully authenticated, subscribing to: #{inspect tickers}"
        {:send, subscribe_frame(tickers), %{state | "ready" => true}}
      [%{"ev" => "status", "status" => "auth_success"}] ->
        Logger.debug "Polygon successfully authenticated, awaiting subscriptions"
        {:nosend, %{state | "ready" => true}}
      [%{"ev" => "status", "status" => "success"}] ->
        {:nosend, state}
      list = [%{"ev" => ev} | _] when ev in ["T", "Q", "A", "AM"] ->
        list
        |> Enum.group_by(&get_ticker/1)
        |> Enum.each(fn {ticker, list} ->
          Xylem.Channel.broadcast(to_topic(ticker), {:data, normalize(list)})
        end)
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

  defp get_ticker(%{"ev" => type, "sym" => symbol}), do: get_ticker(type, symbol)
  defp get_ticker(type, symbol), do: "#{type}.#{symbol}"

  defp to_ticker("polygon:" <> ticker), do: ticker
  defp to_topic(ticker), do: "polygon:" <> ticker

  defp subscribe_frame(tickers) when is_list(tickers), do: json_frame(%{action: "subscribe", params: Enum.join(tickers, ",")})
  defp subscribe_frame(ticker), do: json_frame(%{action: "subscribe", params: ticker})
  defp unsubscribe_frame(ticker), do: json_frame(%{action: "unsubscribe", params: ticker})

  defp json_frame(contents), do: {:text, Jason.encode!(contents)}

  defp normalize(data_list) when is_list(data_list) do
    Logger.debug "unnormalized data: #{inspect data_list}"
    Enum.map(data_list, &normalize/1)
  end

  defp normalize(data) when is_map(data) do
    [:symbol, :price]
    |> Enum.reduce(%{}, &Map.put(&2, &1, normalize(&1, data)))
  end

  defp normalize(:symbol, %{"sym" => symbol}), do: symbol

  defp normalize(:price, %{"ev" => "Q", "bp" => bid, "ap" => ask}) do
    D.div(D.add(to_decimal(bid), to_decimal(ask)), D.new(2))
  end

  defp normalize(:price, %{"ev" => "T", "p" => price}), do: to_decimal(price)
  defp normalize(:price, %{"ev" => "A", "c" => price}), do: to_decimal(price)
  defp normalize(:price, %{"ev" => "AM", "c" => price}), do: to_decimal(price)

  defp normalize(_, _), do: nil

  defp to_decimal(number) when is_float(number), do: D.from_float(number)
  defp to_decimal(number), do: D.new(number)
end
