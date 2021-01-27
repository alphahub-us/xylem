defmodule Heartwood.Venue do
  @moduledoc """
  Behaviour for Heartwood venues. Heartwood expects all venues to broadcast
  order and account updates updates on a well-known channel.
  """

  @doc """
  Retrieves the topic or topics for a venue, provided the given options.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]

  @optional_callbacks topic: 1
end
