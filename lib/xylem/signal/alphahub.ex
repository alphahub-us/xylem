defmodule Xylem.Signal.AlphaHub do
  use Supervisor

  @default_opts [certificates_verification: true, timeout: 5_000]
  @behaviour Xylem.Signal

  alias Xylem.Signal.AlphaHub.Socket


  @impl Xylem.Signal
  def topic(options) do
    case Keyword.fetch(options, :id) do
      {:ok, id} -> {:ok, "alphahub:#{id}"}
      :error -> {:error, :invalid_topic}
    end
  end

  def client(config) do
    middleware = [
      {Tesla.Middleware.BaseUrl, base_url(Keyword.get(config, :env, :prod))},
      {Tesla.Middleware.FormUrlencoded, encode: &form_encode/1},
      Tesla.Middleware.DecodeJson,
    ]

    adapter = {Application.get_env(:tesla, :adapter, Tesla.Adapter.Httpc), Keyword.get(config, :client_opts, @default_opts)}

    Tesla.client(middleware, adapter)
  end

  def create_session(client, params) do
    case Tesla.post(client, "api/v1/session", params) do
      {:ok, response = %{status: status}} when status in 200..299 -> {:ok, response.body["data"]}
      {:ok, %{status: status}} ->{:error, status}
      response -> response
    end
  end

  def start_link(config) do
    Supervisor.start_link(__MODULE__, config, name: get_name(config))
  end

  @impl true
  def init(config) do
    children = [
      {Socket, config}
    ]
    Supervisor.init(children, strategy: :one_for_one)
  end

  defp get_name(config) do
    case Keyword.fetch(config, :name) do
      {:ok, name} -> {:via, Registry, {Xylem.Registry, name, __MODULE__}}
      :error -> __MODULE__
    end
  end

  defp base_url(:prod), do: "https://alphahub.us"
  defp base_url(:dev), do: "http://localhost:8080"

  defp form_encode(%{email: email, password: password}), do: "user[email]=#{email}&user[password]=#{password}"
  defp form_encode(params), do: URI.encode_query(params)
end
