defmodule Microsoft.Azure.Storage.RestClient do
  use Tesla

  adapter Tesla.Adapter.Hackney, recv_timeout: 40_000

  plug Tesla.Middleware.Timeout, timeout: 40_000

  def proxy_middleware() do
    case System.get_env("http_proxy") do
      nil ->
        nil

      "" ->
        nil

      proxy_cfg ->
        proxy_cfg
        |> String.split(":")
        |> (fn [host, port] ->
              {Tesla.Middleware.Opts,
               [
                 # https://github.com/cmullaparthi/ibrowse/wiki/ibrowse-API
                 proxy_host: host |> String.to_charlist(),
                 proxy_port: port |> Integer.parse() |> elem(0)
               ]}
            end).()
    end
  end

  def new(base_url) when is_binary(base_url) do
    [
      {Tesla.Middleware.BaseUrl, base_url},
      proxy_middleware()
    ]
    |> Enum.filter(&(&1 != nil))
    |> Tesla.client()
  end

  def new(base_url, headers) when is_binary(base_url) and is_map(headers) do
    [
      {Tesla.Middleware.BaseUrl, base_url},
      {Tesla.Middleware.Headers, headers},
      proxy_middleware()
    ]
    |> Enum.filter(&(&1 != nil))
    |> Tesla.client()
  end
end
