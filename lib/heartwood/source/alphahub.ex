defmodule Heartwood.Source.AlphaHub do
  @moduledoc """
  The AlphaHub source

  A WebSockets client that listens on the AlphaHub channel for new signals.

  ### Configuration

  To use this source, you pass in your credentials and the IDs of the
  algorithms you wish to monitor via your configuration file:

  ```
  config :heartwood,
    sources: [
      # ...
      alphahub: {
        Heartwood.Source.AlphaHub,
        credentials: %{email: "you@example.com", password: "your password"},
        ids: [1,2,3]
      },
      #...
    ],
  ```

  Then, configure your bot as follows:

  ```
  config :heartwood,
    bots: [
      # ...
      bot_name: {Heartwood.Bot.MyBot, source: {:alphahub, id: 1}, ... }
      # ...
    ]
  ```
  """
  alias Heartwood.Source.AlphaHub.Client

  use Axil

  @behaviour Heartwood.Source

  @impl Heartwood.Source
  def topic(_pid, id: id), do: get_topic(id)

  def start_link(config) do
    with {:ok, credentials} <- Keyword.fetch(config, :credentials),
         {:ok, ids} <- Keyword.fetch(config, :ids),
         {:ok, tokens} = Client.create_session(credentials) do
      path = "/socket/websocket?api_token=#{tokens["token"]}&vsn=2.0.0"
      Axil.start_link([host: "alphahub.us", port: 443, path: path], __MODULE__, %{tokens: tokens, ids: ids})
    else
      :error -> {:error, :bad_args}
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
        Heartwood.Channel.broadcast(get_topic(id), {:source, format(signals)})
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
  defp format(signals), do: signals
end
