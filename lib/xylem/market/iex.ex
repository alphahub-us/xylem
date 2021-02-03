defmodule Xylem.Market.IEx do
  @topic "market:iex"

  @behaviour Xylem.Market

  @impl Xylem.Market
  def topic(_), do: @topic

  def send_event(event), do: Xylem.Channel.broadcast(@topic, {:market, event})
end
