defmodule Xylem.Signal do
  @moduledoc """
  Behaviour for Xylem signals. Xylem expects all signals to broadcast
  new signals on a well-known channel.
  """

  @doc """
  Retrieves the topic or topics for a signal, provided the given options.
  """
  @callback topic(options :: keyword) :: {:ok, String.t | [String.t]}, {:error, :invalid_topic}

  @optional_callbacks topic: 1
end
