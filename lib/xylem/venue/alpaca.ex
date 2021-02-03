defmodule Xylem.Venue.Alpaca do
  use Supervisor
  @behaviour Xylem.Venue

  alias Xylem.Venue.Alpaca.{Socket, Client}

  @impl Xylem.Venue
  def topic(options) do
    case Keyword.fetch(options, :name) do
      {:ok, id} -> {:ok, "alpaca:#{id}"}
      :error -> {:error, :invalid_topic}
    end
  end

  @impl Xylem.Venue
  def submit_order(venue, order, options) do
    case client(venue) do
      {:ok, client} -> Client.submit_order(client, order, options)
      error -> error
    end
  end

  @impl Xylem.Venue
  def cancel_order(venue, order, options) do
    case client(venue) do
      {:ok, client} -> Client.cancel_order(client, order, options)
      error -> error
    end
  end

  @impl Xylem.Venue
  def get_positions(venue) do
    case client(venue) do
      {:ok, client} -> Client.get_positions(client)
      error -> error
    end
  end

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: get_name(config))
  end

  @impl true
  def init(config) do
    children = [
      {Client, config},
      {Socket, config}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp client(venue) do
    Supervisor.which_children(venue)
    |> Enum.filter(& elem(&1, 0) == Client)
    |> case do
      [{Client, pid, _, _}] -> {:ok, pid}
      _ -> {:error, :no_client}
    end
  end

  defp get_name(config) do
    case Keyword.fetch(config, :name) do
      {:ok, name} -> {:via, Registry, {Xylem.Registry, name, __MODULE__}}
      :error -> __MODULE__
    end
  end
end
