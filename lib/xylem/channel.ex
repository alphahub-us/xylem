defmodule Xylem.Channel do
  @moduledoc """
  Wrapper around Phoenix.PubSub. This allows various xylem processes to
  broadcast/subscribe to each other.
  """

  alias Phoenix.PubSub
  @me __MODULE__

  @doc false
  def child_spec(_), do: PubSub.child_spec(name: @me)

  @doc """
  Subscribe to a topic.
  """
  @spec subscribe(binary) :: :ok | {:error, term}
  def subscribe(topic), do: PubSub.subscribe(@me, topic)

  @doc """
  Unsubscribe from a topic.
  """
  @spec unsubscribe(binary) :: :ok | {:error, term}
  def unsubscribe(topic), do: PubSub.unsubscribe(@me, topic)

  @doc """
  Broadcast a message to a topic's subscribers.
  """
  @spec broadcast(binary, term) :: :ok | {:error, term}
  def broadcast(topic, message), do: PubSub.broadcast(@me, topic, message)
end
