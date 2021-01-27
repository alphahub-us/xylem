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
  use Axil

  @behaviour Heartwood.Venue

  @impl Heartwood.Venue
  def topic(_pid, name: name), do: get_topic(name)

  def start_link(config) do
    with {:ok, env} <- Keyword.fetch(config, :env),
         {:ok, _credentials} <- Keyword.fetch(config, :credentials) do
      state = Enum.into(Keyword.take(config, [:credentials, :name]), %{})
      connect_opts = [host: host(env), path: "/stream", port: 443]
      Axil.start_link(connect_opts, __MODULE__, state)
    else
      :error -> {:error, :bad_config}
    end
  end

  def handle_upgrade(_conn, %{credentials: %{id: id, secret: secret}} = state) do
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
        Heartwood.Channel.broadcast(get_topic(state.name), {:venue, data})
        {:nosend, state}
      other ->
        IO.inspect(other, label: "inbound message")
        {:nosend, state}
    end
  end

  def handle_receive(:close, state), do: {:close, state}

  defp get_topic(id), do: "alpaca:#{id}"

  defp host(:paper), do: "paper-api.alpaca.markets"
  defp host(:live), do: "api.alpaca.markets"
  defp json_frame(contents), do: {:text, Jason.encode!(contents)}
end
