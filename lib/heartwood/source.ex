defmodule Heartwood.Source do
  @moduledoc """
  Behaviour for Heartwood sources. Heartwood expects all sources to broadcast
  new signals on a well-known channel.
  """

  @doc """
  Retrieves the topic or topics for a source, provided the given options.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]

  @optional_callbacks topic: 1
end
