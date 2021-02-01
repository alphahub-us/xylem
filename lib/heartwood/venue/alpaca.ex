defmodule Heartwood.Venue.Alpaca do
  @moduledoc """
  The Alpaca venue

  A WebSockets client that listens on the Alpaca account endpoint for account updates.

  ### Configuration

  To use it, you pass in your API or client ID and secret and the
  environment for those keys through your configuration file:

  ```
  config :heartwood,
    venues: [
      # ...
      my_account: {
        Heartwood.Venue.Alpaca,
        credentials: %{id: "alpaca_client_id", secret: "alpaca_secret"},
        env: :paper
      },
      #...
    ],
  ```

  Then, configure your bot as follows:

  ```
  config :heartwood,
    bots: [
      # ...
      bot_name: {Heartwood.Bot.MyBot, venue: :my_account, ... }
      # ...
    ]
  ```
  """
  @dialyzer [
    {:no_match, [handle_sync: 3]}
  ]
  use Axil

  @conn [host: "api.alpaca.markets", path: "/stream", port: 443]

  @behaviour Heartwood.Venue

  @impl Heartwood.Venue
  def topic(name: name), do: get_topic(name)

  @impl Heartwood.Venue
  def submit_order(venue, order, options), do: send(venue, {:submit_order, order, options})

  @impl Heartwood.Venue
  def cancel_order(venue, order, options), do: send(venue, {:cancel_order, order, options})

  @impl Heartwood.Venue
  def get_positions(venue), do: GenServer.call(venue, :positions)

  def start_link(config) do
    with {:ok, env} <- Keyword.fetch(config, :environment),
         {:ok, %{id: id, secret: secret}} <- Keyword.fetch(config, :credentials) do
      client = Alpaca.client([environment: env, id: id, secret: secret])
      state = Enum.into(Keyword.take(config, [:name, :credentials]), %{client: client})
      Axil.start_link(Keyword.merge(@conn, host: host(env)), __MODULE__, state)
    else
      :error -> {:error, :bad_config}
    end
  end

  def handle_sync(:positions, _from, state = %{client: client}) do
    case Alpaca.Positions.list(client) do
      {:ok, positions} ->
        positions = Enum.map(positions, fn %{"qty" => qty, "symbol" => symbol} ->
          %{qty: String.to_integer(qty), symbol: symbol}
        end)
        {:reply, positions, state}
      error -> {:reply, error, state}
    end
  end

  def handle_upgrade(_conn, %{credentials: %{id: id, secret: secret}} = state) do
    Heartwood.Registry.register(state.name, __MODULE__)
    {:send, json_frame(%{action: "authenticate", data: %{key_id: id, secret_key: secret}}), Map.delete(state, :credentials)}
  end

  def handle_receive({type, content}, state) when type in [:text, :binary] do
    content
    |> Jason.decode!()
    |> case do
      %{"stream" => "authorization", "data" => %{"status" => "authorized"}} ->
        {:send, json_frame(%{action: "listen", data: %{streams: ["trade_updates"]}}), state}
      %{"stream" => "authorization", "data" => %{"status" => "unauthorized"}} ->
        {:close, state}
      %{"stream" => "listening"} ->
        IO.puts "listening for Alpaca account updates"
        {:nosend, state}
      %{"stream" => "trade_updates", "data" => data} ->
        Heartwood.Channel.broadcast(get_topic(state.name), {:venue, normalize(data)})
        {:nosend, state}
      other ->
        IO.inspect(other, label: "inbound message")
        {:nosend, state}
    end
  end

  def handle_receive(:close, state), do: {:close, state}

  def handle_other({:submit_order, order, options}, state = %{client: client}) do
    Alpaca.Orders.create(client, to_params(order, Keyword.get(options, :type, :market)))
    {:nosend, state}
  end

  def handle_other({:cancel_order, order, _}, state = %{client: client}) do
    case Alpaca.Orders.retrieve_by_client_order_id(client, order.id) do
      {:ok, order} -> Alpaca.Orders.delete(client, order["id"])
      _ -> :ok
    end
    {:nosend, state}
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
  defp type_params(%{price: price}, :limit), do: %{type: "limit", limit_price: price}

  defp normalize(update) do
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
  defp normalize(:symbol, %{"order" => %{"symbol" => symbol}}), do: symbol
  defp normalize(:side, %{"order" => %{"side" => side}}), do: String.to_existing_atom(side)
  defp normalize(:qty, %{"position_qty" => qty}), do: String.to_integer(qty)
  defp normalize(:qty, %{"order" => %{"qty" => qty}}), do: String.to_integer(qty)
  defp normalize(:price, %{"price" => price}), do: Decimal.new(price)
  defp normalize(:price, %{"order" => %{"limit_price" => price}}), do: Decimal.new(price)
  defp normalize(:price, %{"order" => %{"filled_avg_price" => price}}), do: Decimal.new(price)
  defp normalize(_, _), do: nil

  defp get_topic(id), do: "alpaca:#{id}"

  defp host("paper"), do: "paper-api.alpaca.markets"
  defp host("live"), do: "api.alpaca.markets"
  defp json_frame(contents), do: {:text, Jason.encode!(contents)}
end
