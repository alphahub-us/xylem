defmodule Heartwood.Market.IEx do
  @topic "market:iex"

  @behaviour Heartwood.Market

  @impl Heartwood.Market
  def topic(_), do: @topic

  def send_event(event), do: Heartwood.Channel.broadcast(@topic, {:market, event})
end
