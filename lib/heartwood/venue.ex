defmodule Heartwood.Venue do
  @moduledoc """
  Behaviour for Heartwood venues. Heartwood expects all venues to broadcast
  order and account updates updates on a well-known channel.
  """

  @typedoc """
  Venue order events. These are updates sent by the venue on a given order.
  """
  @type order_event :: %{
    id: String.t,
    timestamp: NaiveDateTime.t,
    type: :fill | :partial | :new | :cancel,
    symbol: String.t,
    side: :buy | :sell,
    qty: non_neg_integer,
    price: float,
  }

  @doc """
  Retrieves the topic or topics for a venue, provided the given options.
  """
  @callback topic(options :: keyword) :: String.t | [String.t]

  @doc """
  Submits an order to the venue
  """
  @callback submit_order(order :: map, options :: keyword) :: :ok
  @callback submit_order(venue :: pid, order :: map, options :: keyword) :: :ok

  @doc """
  Submits an order cancellation request to the venue
  """
  @callback cancel_order(order :: map, options :: keyword) :: :ok
  @callback cancel_order(venue :: pid, order :: map, options :: keyword) :: :ok

  @doc """
  gets the positions from the venue
  """
  @callback get_positions() :: :ok
  @callback get_positions(venue :: pid) :: :ok

  @optional_callbacks topic: 1, submit_order: 2, submit_order: 3, cancel_order: 2,
  cancel_order: 3, get_positions: 0, get_positions: 1

  @spec event_to_csv(order_event) :: String.t
  def event_to_csv(event) do
    [:timestamp,:type,:side,:symbol,:qty,:price]
    |> Enum.map(&Map.get(event, &1))
    |> Enum.reject(&is_nil/1)
    |> Enum.join(",")
  end

  def submit_order(venue_name, order, options \\ []) do
    venue_name
    |> Heartwood.Registry.lookup()
    |> case do
      {pid, module} -> apply(module, :submit_order, [pid, order, options])
      _ -> apply(venue_name, :submit_order, [order, options])
    end
  end

  def cancel_order(venue_name, order, options \\ []) do
    venue_name
    |> Heartwood.Registry.lookup()
    |> case do
      {pid, module} -> apply(module, :cancel_order, [pid, order, options])
      _ -> apply(venue_name, :cancel_order, [order, options])
    end
  end

  def get_positions(venue_name) do
    venue_name
    |> Heartwood.Registry.lookup()
    |> case do
      {pid, module} -> apply(module, :get_positions, [pid])
      _ -> apply(venue_name, :get_positions, [])
    end
  end
end
