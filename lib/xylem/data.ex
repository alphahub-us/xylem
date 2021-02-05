defmodule Xylem.Data do
  @moduledoc """
  Behaviour for Xylem data sources. Xylem expects all data sources to broadcast
  asset updates on well-known channels.
  """

  @doc """
  Retrieves the topic or topics for a market, provided the given options.
  """
  @callback topic(options :: term) :: {:ok, String.t | [String.t]} | {:error, :invalid_topic}
  @callback subscribe(data :: pid | module, topic :: term) :: :ok | {:error, term}
  @callback unsubscribe(data :: pid | module, topic :: term) :: :ok | {:error, term}

  @optional_callbacks topic: 1, subscribe: 2, unsubscribe: 2

  def topic(data_name, options) do
    case Xylem.Bot.get_topic_module(data_name) do
      nil -> {:error, :data_not_found}
      module -> apply(module, :topic, [options])
    end
  end

  def subscribe(data_name, topic) do
    {pid, mod} = get_module_data(data_name)
    if exports?(mod, :subscribe, 2), do: apply(mod, :subscribe, [pid, topic])
  end

  def unsubscribe(data_name, topic) do
    {pid, mod} = get_module_data(data_name)
    if exports?(mod, :subscribe, 2), do: apply(mod, :unsubscribe, [pid, topic])
  end

  defp get_module_data(name) do
    case Xylem.Registry.lookup(name) do
      nil -> {nil, name}
      result -> result
    end
  end

  defp exports?(mod, func, arity) do
    Enum.all?([&Code.ensure_loaded?/1, &function_exported?(&1, func, arity)], & &1.(mod))
  end
end
