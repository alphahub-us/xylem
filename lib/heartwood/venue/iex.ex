defmodule Heartwood.Venue.IEx do
  @topic "venue:iex"

  @behaviour Heartwood.Venue

  @impl Heartwood.Venue
  def topic(_), do: @topic

  def update(order), do: Heartwood.Channel.broadcast(@topic, {:venue, order})
end
