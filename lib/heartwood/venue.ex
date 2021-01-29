defmodule Heartwood.Venue do
  @moduledoc """
  Behaviour for Heartwood venues. Heartwood expects all venues to broadcast
  order and account updates updates on a well-known channel.
  """

  @typedoc """
  Venue order events. These are updates sent by the venue on a given order.
  """
  @type order_event :: %{
    timestamp: NaiveDateTime.t,
    type: :fill | :partial_fill | :new | :cancelled,
    side: :buy | :sell,
    symbol: String.t,
    qty: integer,
    price: float
  }

  @doc """
  Retrieves the topic or topics for a venue, provided the given options.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]

  @optional_callbacks topic: 1

  @spec event_to_csv(order_event) :: String.t
  def event_to_csv(event) do
    [:timestamp,:type,:side,:symbol,:qty,:price]
    |> Enum.map(&Map.get(event, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end
end
