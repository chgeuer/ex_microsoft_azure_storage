defmodule Microsoft.Azure.Storage.RequestBuilder do
  import SweetXml
  alias Microsoft.Azure.Storage
  alias Microsoft.Azure.Storage.RestClient
  alias Microsoft.Azure.Storage.ApiVersion
  alias Microsoft.Azure.Storage.DateTimeUtils

  @json_library Application.get_env(:ex_microsoft_azure_storage, :json_library, Jason)

  def new_azure_storage_request, do: %{}

  def method(request, m), do: request |> Map.put_new(:method, m)

  def url(request, u), do: request |> Map.put_new(:url, u)

  def body(request, body),
    do:
      request
      |> add_header("Content-Length", "#{body |> byte_size()}")
      |> Map.put(:body, body)

  def add_header_content_md5(request) do
    body = request |> Map.get(:body)
    md5 = :crypto.hash(:md5, body) |> Base.encode64()

    request
    |> add_header("Content-MD5", md5)
  end

  def add_header_if(request, false, _k, _v), do: request
  def add_header_if(request, true, k, v), do: request |> add_header(k, v)

  # request |> Map.update!(:headers, &Map.merge(&1, headers))
  def add_header(request = %{headers: headers}, k, v) when headers != nil,
    do: request |> Map.put(:headers, headers |> Map.put(k, v))

  def add_header(request, k, v), do: request |> Map.put(:headers, %{k => v})

  @prefix_x_ms_meta "x-ms-meta-"

  def add_header_x_ms_meta(request, kvp = %{}),
    do:
      kvp
      |> Enum.reduce(request, fn {k, v}, r -> r |> add_header(@prefix_x_ms_meta <> k, v) end)

  def extract_x_ms_meta_headers(response) do
    response.headers
    |> Enum.filter(fn {k, _v} -> String.starts_with?(k, @prefix_x_ms_meta) end)
    |> Enum.map(fn {@prefix_x_ms_meta <> k, v} -> {k, v} end)
    |> Enum.into(%{})
  end

  def add_optional_params(request, _, []), do: request

  def add_optional_params(request, definitions, [{key, value} | tail]) do
    case definitions do
      %{^key => location} ->
        request
        |> add_param(location, key, value)
        |> add_optional_params(definitions, tail)

      _ ->
        add_optional_params(request, definitions, tail)
    end
  end

  def add_param_if(request, false, _location, _key, _value), do: request

  def add_param_if(request, true, location, key, value),
    do: request |> add_param(location, key, value)

  def add_param(request, :body, :body, value), do: request |> Map.put(:body, value)

  def add_param(request, :body, key, value) do
    request
    |> Map.put_new_lazy(:body, &Tesla.Multipart.new/0)
    |> Map.update!(
      :body,
      &Tesla.Multipart.add_field(
        &1,
        key,
        @json_library.encode!(value),
        headers: [{:"Content-Type", "application/json"}]
      )
    )
  end

  def add_param(request, :file, name, path) do
    request
    |> Map.put_new_lazy(:body, &Tesla.Multipart.new/0)
    |> Map.update!(:body, &(&1 |> Tesla.Multipart.add_file(path, name: name)))
  end

  def add_param(request, :form, name, value) do
    request
    |> Map.update(:body, %{name => value}, &(&1 |> Map.put(name, value)))
  end

  def add_param(request, location, key, value) do
    request
    |> Map.update(location, [{key, value}], &(&1 ++ [{key, value}]))
  end

  def add_param(request, :query, opts) when is_list(opts) do
    filtered_opts = opts |> only_non_empty_values

    new_q =
      case request[:query] do
        nil -> filtered_opts
        query -> query ++ filtered_opts
      end

    request
    |> Map.put(:query, new_q)
  end

  defp only_non_empty_values(opts) when is_list(opts),
    do:
      opts
      |> Enum.filter(fn {_, value} -> value != nil && value != "" end)
      |> Enum.into([])

  def add_storage_context(request, storage_context = %Storage{}),
    do: request |> Map.put_new(:storage_context, storage_context)

  def add_ms_context(request, storage_context, date, service) do
    request
    |> add_storage_context(storage_context)
    |> add_header("x-ms-date", date)
    |> add_header("x-ms-version", service |> ApiVersion.get_api_version())
  end

  defp primary(account_name), do: account_name |> String.replace("-secondary", "")

  defp canonicalized_headers(headers = %{}),
    do:
      headers
      |> Enum.into([])
      |> Enum.map(fn {k, v} -> {k |> String.downcase(), v} end)
      |> Enum.filter(fn {k, _} -> k |> String.starts_with?("x-ms-") end)
      |> Enum.sort()
      |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
      |> Enum.join("\n")

  def remove_empty_headers(request = %{headers: headers = %{}}) do
    new_headers =
      headers
      |> Enum.into([])
      |> Enum.filter(fn {_k, v} -> v != nil && String.length(v) > 0 end)
      |> Enum.into(%{})

    request
    |> Map.put(:headers, new_headers)
  end

  defp get_header(headers, name) do
    headers
    |> Map.get(name)
  end

  defp protect(
         # https://docs.microsoft.com/en-us/rest/api/storageservices/authentication-for-the-azure-storage-services

         data = %{
           method: method,
           url: url,
           query: query,
           headers: headers = %{},
           storage_context:
             storage_context = %Storage{
               is_development_factory: is_development_factory,
               account_key: account_key
             }
         }
       )
       when is_binary(account_key) and account_key != nil do
    canonicalizedHeaders = headers |> canonicalized_headers()

    url =
      case is_development_factory do
        true -> "/devstoreaccount1#{url}"
        _ -> url
      end

    canonicalizedResource =
      case query do
        [] ->
          "/#{storage_context.account_name |> primary()}#{url}"

        _ ->
          "/#{storage_context.account_name |> primary()}#{url}\n" <>
            (query
             |> Enum.sort_by(& &1)
             |> Enum.map_join("\n", fn {k, v} -> "#{k}:#{v}" end))
      end

    stringToSign =
      [
        method |> Atom.to_string() |> String.upcase(),
        headers |> get_header("Content-Encoding"),
        headers |> get_header("Content-Language"),
        headers |> get_header("Content-Length"),
        headers |> get_header("Content-MD5"),
        headers |> get_header("Content-Type"),
        headers |> get_header("Date"),
        headers |> get_header("If-Modified-Since"),
        headers |> get_header("If-Match"),
        headers |> get_header("If-None-Match"),
        headers |> get_header("If-Unmodified-Since"),
        headers |> get_header("Range"),
        canonicalizedHeaders,
        canonicalizedResource
      ]
      |> Enum.join("\n")

    signature =
      :crypto.hmac(:sha256, storage_context.account_key |> Base.decode64!(), stringToSign)
      |> Base.encode64()

    data
    |> add_header(
      "Authorization",
      "SharedKey #{storage_context.account_name |> primary()}:#{signature}"
    )
  end

  defp protect(
         request = %{
           storage_context: %Storage{account_key: nil, aad_token_provider: aad_token_provider},
           uri: uri
         }
       ) do
    audience = uri |> trim_uri_for_aad_request()

    request
    |> add_header("Authorization", "Bearer #{aad_token_provider.(audience)}")
  end

  defp trim_uri_for_aad_request(uri) when is_binary(uri) do
    %URI{host: host, scheme: scheme} = uri |> URI.parse()

    %URI{host: host, scheme: scheme}
    |> URI.to_string()
  end

  def sign_and_call(
        request = %{storage_context: storage_context = %Storage{}},
        service
      )
      when is_atom(service) do
    uri =
      storage_context
      |> Storage.endpoint_url(service)

    connection =
      uri
      |> RestClient.new()

    request
    |> remove_empty_headers()
    |> add_missing(:query, [])
    |> Map.put(:uri, uri)
    |> protect()
    |> Enum.into([])
    |> (&RestClient.request(connection, &1)).()
  end

  def add_missing(map, key, value) do
    case map do
      %{^key => _} -> map
      %{} -> map |> Map.put(key, value)
    end
  end

  def decode(%Tesla.Env{status: 200, body: body}), do: @json_library.decode(body)
  def decode(response), do: {:error, response}
  def decode(%Tesla.Env{status: 200} = env, false), do: {:ok, env}

  def decode(%Tesla.Env{status: 200, body: body}, struct),
    do: @json_library.decode(body, as: struct)

  def decode(response, _struct), do: {:error, response}

  def create_error_response(response = %{}) do
    {:error,
     response.body
     |> xmap(
       code: ~x"/Error/Code/text()"s,
       message: ~x"/Error/Message/text()"s,
       authentication_error_detail: ~x"/Error/AuthenticationErrorDetail/text()"s,
       query_parameter_name: ~x"/Error/QueryParameterName/text()"s,
       query_parameter_value: ~x"/Error/QueryParameterValue/text()"s
     )
     |> Map.update!(:message, &String.split(&1, "\n"))
     |> Map.put(:status, response.status)
     |> Map.put(:url, response.url)
     |> Map.put(:body, response.body)
     |> Map.put(:request_id, response.headers["x-ms-request-id"])}
  end

  def identity(x), do: x

  def add_if_header_exists_in_response(
        map,
        response,
        header_str,
        key,
        transformer \\ &__MODULE__.identity/1
      )
      when is_map(map) and is_map(response) and is_binary(header_str) and is_atom(key) do
    case(response.headers[header_str]) do
      nil -> map
      val -> map |> Map.put(key, transformer.(val))
    end
  end

  def create_success_response(response, map \\ %{}) do
    map
    |> Map.put(:status, response.status)
    |> Map.put(:headers, response.headers)
    |> Map.put(:request_url, response.url)
    |> add_if_header_exists_in_response(
      response,
      "last-modified",
      :last_modified,
      &DateTimeUtils.parse_rfc1123/1
    )
    |> add_if_header_exists_in_response(response, "date", :date, &DateTimeUtils.parse_rfc1123/1)
    |> add_if_header_exists_in_response(response, "x-ms-request-id", :request_id)
    |> add_if_header_exists_in_response(
      response,
      "expires",
      :expires,
      &DateTimeUtils.parse_rfc1123/1
    )
    |> add_if_header_exists_in_response(response, "etag", :etag)
    |> Map.put(:body, response.body)
  end

  def to_bool("true"), do: true
  def to_bool("false"), do: false
  def to_bool(_), do: false
end
