defmodule Xylem.Signal.AlphaHub do
  use Axil

  @default_opts [certificates_verification: true, timeout: 5_000]
  @behaviour Xylem.Signal

  require Logger

  @impl Xylem.Signal
  def topic(options) do
    case Keyword.fetch(options, :id) do
      {:ok, id} -> {:ok, "alphahub:#{id}"}
      :error -> {:error, :invalid_topic}
    end
  end

  def start_link(config) do
    with {:ok, credentials} <- Keyword.fetch(config, :credentials),
         client = client(config),
         {:ok, tokens} <- create_session(client, credentials) do
      path = "/socket/websocket?api_token=#{tokens["token"]}&vsn=2.0.0"
      state = Enum.into(Keyword.take(config, [:ids, :credentials]), %{})
      conn = conn_info(Keyword.get(config, :env, :prod))
      Axil.start_link(Keyword.merge(conn, path: path), __MODULE__, state, name: get_name(config))
    else
      :error -> {:error, :bad_args}
      error = {:error, _} -> error
    end
  end

  defp client(config) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url(Keyword.get(config, :env, :prod))},
      {Tesla.Middleware.FormUrlencoded, encode: &form_encode/1},
      Tesla.Middleware.DecodeJson,
    ]

    adapter = {Application.get_env(:tesla, :adapter, Tesla.Adapter.Httpc), @default_opts}

    Tesla.client(middleware, adapter)
  end

  defp create_session(client, params) do
    case Tesla.post(client, "api/v1/session", params) do
      {:ok, response = %{status: status}} when status in 200..299 -> {:ok, response.body["data"]}
      {:ok, %{status: status}} ->{:error, status}
      response -> response
    end
  end

  defp get_name(config) do
    case Keyword.fetch(config, :name) do
      {:ok, name} -> {:via, Registry, {Xylem.Registry, name, __MODULE__}}
      :error -> __MODULE__
    end
  end

  defp base_url(:prod), do: "https://alphahub.us"
  defp base_url(:dev), do: "http://localhost:8080"

  defp conn_info(:prod), do: [host: "alphahub.us", port: 443]
  defp conn_info(:dev), do: [host: "localhost", port: 8080]

  defp form_encode(%{email: email, password: password}), do: "user[email]=#{email}&user[password]=#{password}"
  defp form_encode(params), do: URI.encode_query(params)

  # Axil overrides

  # Start subscribing to the desired algorithm channels once we've connected
  def handle_upgrade(_conn, %{ids: ids} = state) do
    Process.send_after(self(), {:subscribe, ids}, 0)
    {:nosend, state}
  end

  def handle_receive({:text, content}, state) do
    content
    |> Jason.decode!()
    |> case do
      [_, _, "algorithms:" <> id, "new_signals", signals] ->
        {:ok, topic} = topic(id: id)
        Xylem.Channel.broadcast(topic, {:signal, normalize(signals)})
      [_, _, _topic, "phx_reply", %{ "status" => "ok" }] -> :ok
      message -> IO.inspect(message)
    end
    {:nosend, state}
  end

  def handle_receive(:close, state), do: {:close, state}

  def handle_receive({:close, 1000, _}, state) do
    Logger.warn "AlphaHub socket closed normally"
    {:close, state}
  end

  def handle_other({:subscribe, []}, state) do
    Logger.debug "listening for AlphaHub signals..."
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

  defp json_frame(contents), do: {:text, Jason.encode!(contents)}

  defp normalize(signals) do
    signals
    |> Enum.map(fn
      {type, signals} when is_list(signals) and length(signals) > 0 ->
        signals = Enum.reject(signals, & &1["side"] == "hold")
        defaults = [type: String.to_existing_atom(type), weight: default_weight(signals)]
        Enum.map(signals, &normalize(&1, defaults))
      _ ->
        []
    end)
    |> List.flatten()
  end

  defp normalize(signal, defaults) do
    keys = [:type, :symbol, :price, :side, :weight]

    signal = signal |> Enum.into(%{}, &normalize_pair/1) |> Map.take(keys) |> fix_invalid_symbols()
    defaults = defaults |> Keyword.take(keys) |> Enum.into(%{})

    Map.merge(defaults, signal)
  end

  defp fix_invalid_symbols(signal = %{symbol: "MYL"}), do: %{signal | symbol: "VTRS"}
  defp fix_invalid_symbols(signal), do: signal

  defp normalize_pair({k,v}), do: {String.to_existing_atom(k), normalize_value(k,v)}

  defp normalize_value(k, v) when k in ["price", "weight"], do: to_decimal(v)
  defp normalize_value(k, v) when k in ["type", "side"], do: String.to_existing_atom(v)
  defp normalize_value(_, v), do: v

  defp default_weight([]), do: Decimal.new("0")
  defp default_weight(signals), do: Decimal.div(Decimal.new(1), Decimal.new(length(signals)))

  defp to_decimal(price) when is_float(price), do: Decimal.from_float(price)
  defp to_decimal(price), do: Decimal.new(price)
end
