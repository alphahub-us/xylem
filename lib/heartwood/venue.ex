defmodule Heartwood.Venue do
  @moduledoc """
  Behaviour for Heartwood venues. Heartwood expects all venues to broadcast
  order and account updates updates on a well-known channel.
  """

  @doc """
  Retrieves the topic or topics for a venue, provided the given options.

  Venues that use processes should implement `topic/2`. Other venues should
  implement `topic/1`.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]
  @callback topic(venue :: pid, options :: keyword) :: String.t | [String.t]

  @optional_callbacks topic: 1, topic: 2
end
