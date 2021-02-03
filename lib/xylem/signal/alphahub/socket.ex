defmodule Xylem.Signal.AlphaHub.Socket do
  @moduledoc """
  A WebSockets client that listens on the AlphaHub channel for new signals.

  ### Configuration

  To use this signal, you pass in your credentials and the IDs of the
  algorithms you wish to monitor via your configuration file:

  ```
  config :xylem,
    signals: [
      # ...
      alphahub: {
        Xylem.Signal.AlphaHub,
        credentials: %{email: "you@example.com", password: "your password"},
        ids: [1,2,3]
      },
      #...
    ],
  ```

  Then, configure your bot as follows:

  ```
  config :xylem,
    bots: [
      # ...
      bot_name: {Xylem.Bot.MyBot, signal: {:alphahub, id: 1}, ... }
      # ...
    ]
  ```
  """
  alias Xylem.Signal.AlphaHub.Client

  use Axil

  @conn [host: "alphahub.us", path: "/", port: 443]

  @behaviour Xylem.Signal

  @impl Xylem.Signal
  def topic(id: id), do: get_topic(id)

  def start_link(config) do
    with {:ok, credentials} <- Keyword.fetch(config, :credentials),
         {:ok, _ids} <- Keyword.fetch(config, :ids),
         {:ok, tokens} <- Client.create_session(credentials) do
      path = "/socket/websocket?api_token=#{tokens["token"]}&vsn=2.0.0"
      state = Enum.into(Keyword.take(config, [:ids, :credentials]), %{})
      Axil.start_link(Keyword.merge(@conn, path: path), __MODULE__, state)
    else
      :error -> {:error, :bad_args}
      error = {:error, _} -> error
    end
  end

  # Axil overrides

  # Start subscribing to the desired algorithm channels once we've connected
  def handle_upgrade(_conn, %{ids: ids} = state) do
    Process.send_after(self(), {:subscribe, ids}, 0)
    {:nosend, state}
  end

  def handle_receive({:text, content}, state) do
    content
    |> Jason.decode()
    |> case do
      {:ok, [_, _, "algorithms:" <> id, "new_signals", signals]} ->
        Xylem.Channel.broadcast(get_topic(id), {:signal, normalize(signals)})
      {:ok, [_, _, _topic, "phx_reply", %{ "status" => "ok" }]} ->
        :ok
      {:ok, message} ->
        IO.inspect(message)
      {:error, _} ->
        IO.inspect(content)
    end
    {:nosend, state}
  end

  def handle_receive(:close, state), do: {:close, state}

  def handle_receive({:close, 1000, _}, state) do
    IO.puts "AlphaHub socket closed normally"
    {:close, state}
  end

  def handle_other({:subscribe, []}, state) do
    IO.puts "listening for AlphaHub signals..."
    Process.send_after(self(), :send_heartbeat, 30_000)
    {:nosend, state}
  end

  def handle_other({:subscribe, [id | ids]}, state) do
    Process.send_after(self(), {:subscribe, ids}, 0)
    {:send, json_frame([nil, nil, "algorithms:#{id}", "phx_join", %{}]), state}
  end

  # Need to send a heartbeat signal to keep the connection open for longer than a minute
  def handle_other(:send_heartbeat, state) do
    Process.send_after(self(), :send_heartbeat, 30_000)
    {:send, json_frame([nil, nil, "phoenix", "heartbeat", %{}]), state}
  end

  defp get_topic(id), do: "alphahub:#{id}"
  defp json_frame(contents), do: {:text, Jason.encode!(contents)}

  defp normalize(signals) do
    signals
    |> Enum.map(fn
      {type, signals} when is_list(signals) and length(signals) > 0 ->
        defaults = [type: String.to_existing_atom(type), weight: default_weight(signals)]
        Enum.map(signals, &normalize(&1, defaults))
      _ ->
        []
    end)
    |> List.flatten()
  end

  defp normalize(signal, defaults) do
    keys = [:type, :symbol, :price, :side, :weight]

    signal = signal |> Enum.into(%{}, &normalize_pair/1) |> Map.take(keys)
    defaults = defaults |> Keyword.take(keys) |> Enum.into(%{})

    Map.merge(defaults, signal)
  end

  defp normalize_pair({k,v}), do: {String.to_existing_atom(k), normalize_value(k,v)}

  defp normalize_value(k, v) when k in ["price", "weight"], do: to_decimal(v)
  defp normalize_value(k, v) when k in ["type", "side"], do: String.to_existing_atom(v)
  defp normalize_value(_, v), do: v

  defp default_weight(signals), do: Decimal.div(Decimal.new(1), Decimal.new(length(signals)))

  defp to_decimal(price) when is_float(price), do: Decimal.from_float(price)
  defp to_decimal(price), do: Decimal.new(price)
end
