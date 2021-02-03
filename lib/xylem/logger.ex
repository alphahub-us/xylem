defmodule Xylem.Logger do
  @moduledoc """
  A module that handles logging for bots.

  To start logging:
  ```
  iex> Xylem.Logger.start(name: :my_bot, path: "/tmp/my_bot")
  :ok
  iex> order_event = %{timestamp: ~N[2021-01-01 12:00:00], symbol: "AAPL", shares: 10, price: 123.456}
  %{timestamp: ~N[2021-01-01 12:00:00], symbol: "AAPL", shares: 10, price: 123.456}
  iex> Xylem.Logger.record_order_event(:my_bot, order_event, format: :csv)
  :ok # should log the order to the desired file
  ```
  """

  require Logger

  def start(options) do
    with {:ok, id} <- Keyword.fetch(options, :name),
         {:ok, _pid} <- Logger.add_backend({LoggerFileBackend, id}) do
      Logger.configure_backend({LoggerFileBackend, id}, extract_config(options))
    else
      :error -> {:error, :no_logger_id}
      {:error, :already_present} -> :ok
    end
  end

  @spec record_order_event(atom, map, (Xylem.Venue.order_event -> String.t)) :: :ok
  def record_order_event(id, event, formatter \\ &to_string/1) do
    Logger.info(formatter.(event), id: id)
  end

  defp extract_config([]), do: [{:format, "$message\n"}, {:level, :info}]
  defp extract_config([{:log_path, path} | rest]), do: [{:path, path} | extract_config(rest)]
  defp extract_config([{:name, id} | rest]), do: [{:metadata_filter, [id: id]} | extract_config(rest)]
  defp extract_config([_other | rest]), do: extract_config(rest)
end
