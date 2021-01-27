defmodule Heartwood.Market do
  @moduledoc """
  Behaviour for Heartwood markets. Heartwood expects all markets to broadcast
  asset updates on well-known channels.
  """

  @doc """
  Retrieves the topic or topics for a market, provided the given options.

  Markets that use processes should implement `topic/2`. Other markets should
  implement `topic/1`.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]
  @callback topic(market :: pid, options :: keyword) :: String.t | [String.t]

  @optional_callbacks topic: 1, topic: 2
end
