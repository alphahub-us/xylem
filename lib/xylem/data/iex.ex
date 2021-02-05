defmodule Xylem.Data.IEx do
  @topic "data:iex"

  @behaviour Xylem.Data

  @impl Xylem.Data
  def topic(_), do: {:ok, @topic}

  def send_event(event), do: Xylem.Channel.broadcast(@topic, {:data, event})
end
