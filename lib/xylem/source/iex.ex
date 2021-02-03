defmodule Xylem.Source.IEx do
  @topic "source:iex"

  @behaviour Xylem.Source

  @impl Xylem.Source
  def topic(_), do: @topic

  def submit(signals), do: Xylem.Channel.broadcast(@topic, {:source, signals})
end
