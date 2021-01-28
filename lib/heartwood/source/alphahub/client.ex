defmodule Heartwood.Source.AlphaHub.Client do

  use Tesla

  plug Tesla.Middleware.BaseUrl, "https://alphahub.us"
  plug Tesla.Middleware.DecodeJson
  plug Tesla.Middleware.FormUrlencoded, encode: &form_encode/1

  @adapter_opts [adapter: [certificates_verification: true, timeout: 5_000]]

  def create_session(params) do
    handle_response(post("api/v1/session", params, opts: @adapter_opts))
  end

  defp form_encode(%{email: email, password: password}), do: "user[email]=#{email}&user[password]=#{password}"
  defp form_encode(params), do: URI.encode_query(params)

  defp handle_response({:ok, response = %{status: status}}) when status in 200..299, do: {:ok, response.body["data"]}
  defp handle_response({:ok, %{status: status}}), do: {:error, status}
  defp handle_response(response), do: response
end
