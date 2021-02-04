defmodule Xylem.Data do
  @moduledoc """
  Behaviour for Xylem data sources. Xylem expects all data sources to broadcast
  asset updates on well-known channels.
  """

  @doc """
  Retrieves the topic or topics for a market, provided the given options.
  """
  @callback topic(options :: term) :: {:ok, String.t | [String.t]} | {:error, :invalid_topic}

  @optional_callbacks topic: 1

  def topic(data_name, options) do
    case Xylem.Registry.lookup(data_name) do
      {_pid, module} -> apply(module, :topic, [options])
      _ -> {:error, :data_not_found}
    end
  end
end
