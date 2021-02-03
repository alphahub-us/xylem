defmodule Xylem.Data do
  @moduledoc """
  Behaviour for Xylem data sources. Xylem expects all data sources to broadcast
  asset updates on well-known channels.
  """

  @doc """
  Retrieves the topic or topics for a market, provided the given options.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]

  @optional_callbacks topic: 1
end
