defmodule Xylem.Venue.IEx do
  @topic "venue:iex"

  @behaviour Xylem.Venue

  @impl Xylem.Venue
  def topic(_), do: {:ok, @topic}

  def update(order), do: Xylem.Channel.broadcast(@topic, {:venue, order})
end
