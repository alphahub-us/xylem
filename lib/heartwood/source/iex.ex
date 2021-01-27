defmodule Heartwood.Source.IEx do
  @topic "source:iex"

  @behaviour Heartwood.Source

  @impl Heartwood.Source
  def topic(_), do: @topic

  def submit(signals), do: Heartwood.Channel.broadcast(@topic, {:source, signals})
end
