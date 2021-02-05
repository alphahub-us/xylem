defmodule Xylem.Signal.IEx do
  @topic "signal:iex"

  @behaviour Xylem.Signal

  @impl Xylem.Signal
  def topic(_), do: {:ok, @topic}

  def submit(signals), do: Xylem.Channel.broadcast(@topic, {:signal, signals})
end
