defmodule Xylem.Data.IEx do
  @topic "data:iex"

  @behaviour Xylem.Data

  @impl Xylem.Data
  def topic(_), do: @topic

  def send_event(event), do: Xylem.Channel.broadcast(@topic, {:market, event})
end
