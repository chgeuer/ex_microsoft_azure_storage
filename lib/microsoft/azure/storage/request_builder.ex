defmodule Microsoft.Azure.Storage.RequestBuilder do
  import SweetXml
  alias Microsoft.Azure.Storage
  alias Microsoft.Azure.Storage.{RestClient, ApiVersion, DateTimeUtils, Container}

  @json_library Application.get_env(:ex_microsoft_azure_storage, :json_library, Jason)

  def new_azure_storage_request(storage = %Storage{}), do: %{storage_context: storage}

  def method(request, m), do: request |> Map.put_new(:method, m)

  def url(request, u), do: request |> Map.put_new(:url, u)

  def body(request, body) do
    request
    |> add_header("Content-Length", "#{body |> byte_size()}")
    |> Map.put(:body, body)
  end

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
    do: request |> Map.put(:headers, [{k, v} | headers])

  def add_header(request, k, v), do: request |> Map.put(:headers, [{k, v}])

  @prefix_x_ms_meta "x-ms-meta-"

  def add_header_x_ms_meta(request, kvp = %{}),
    do:
      kvp
      |> Enum.reduce(request, fn {k, v}, r -> r |> add_header(@prefix_x_ms_meta <> k, v) end)

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

  defp primary(account_name), do: account_name |> String.replace("-secondary", "")

  defp canonicalized_headers(headers) do
    headers
    |> Enum.map(fn {k, v} -> {k |> String.downcase(), v} end)
    |> Enum.filter(fn {k, _} -> k |> String.starts_with?("x-ms-") end)
    |> Enum.sort()
    |> Enum.map(fn {k, v} -> "#{k}:#{v}" end)
    |> Enum.join("\n")
  end

  def remove_empty_headers(request = %{headers: headers}) when is_list(headers) do
    new_headers =
      headers
      |> Enum.filter(fn {_k, v} -> v != nil && String.length(v) > 0 end)

    request
    |> Map.put(:headers, new_headers)
  end

  defp get_header(headers, name) do
    case for {k, v} <- headers, k == name, do: v do
      [result] -> result
      [] -> nil
    end
  end

  defp protect(
         # https://docs.microsoft.com/en-us/rest/api/storageservices/authentication-for-the-azure-storage-services

         data = %{
           method: method,
           url: url,
           query: query,
           headers: headers,
           storage_context:
             storage_context = %Storage{
               is_development_factory: is_development_factory,
               account_key: account_key,
               aad_token_provider: nil
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
      :hmac
      |> :crypto.mac(:sha256, storage_context.account_key |> Base.decode64!(), stringToSign)
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
    token =
      uri
      |> trim_uri_for_aad_request()
      |> aad_token_provider.()

    request
    |> add_header("Authorization", "Bearer #{token}")
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
      when is_atom(service) and service in [:blob_service, :queue_service, :table_service] do
    uri =
      storage_context
      |> Storage.endpoint_url(service)

    connection =
      uri
      |> RestClient.new()

    request
    |> add_header_if(request.method == :put, "Content-Type", "application/octet-stream")
    |> add_header("x-ms-date", DateTimeUtils.utc_now())
    |> add_header("x-ms-version", ApiVersion.get_api_version(:storage))
    |> remove_empty_headers()
    |> add_missing(:query, [])
    |> Map.put(:uri, uri)
    |> protect()
    |> Enum.into([])
    |> (&RestClient.request(connection, &1)).()
    |> elem(1)
  end

  def add_missing(map, key, value) do
    case map do
      %{^key => _} -> map
      %{} -> map |> Map.put(key, value)
    end
  end

  defmodule Responses do
    def error_response(),
      do: [
        error_code: ~x"/Error/Code/text()"s,
        error_message: ~x"/Error/Message/text()"s,
        authentication_error_detail: ~x"/Error/AuthenticationErrorDetail/text()"s,
        query_parameter_name: ~x"/Error/QueryParameterName/text()"s,
        query_parameter_value: ~x"/Error/QueryParameterValue/text()"s
      ]
  end

  def identity(x), do: x
  def to_bool("true"), do: true
  def to_bool("false"), do: false
  def to_bool(_), do: false

  def to_integer!(x) do
    {i, ""} = x |> Integer.parse()
    i
  end

  def create_error_response(response = %{}) do
    response
    |> create_success_response(xml_body_parser: &__MODULE__.Responses.error_response/0)
    |> Map.update!(:error_message, &String.split(&1, "\n"))
  end

  def create_success_response(response, opts \\ []) do
    Map.new()
    |> Map.put(:request_url, response.url)
    |> Map.put(:status, response.status)
    |> Map.put(:headers, response.headers)
    |> Map.put(:body, response.body)
    |> copy_response_headers_into_map()
    |> copy_x_ms_meta_headers_into_map()
    |> (fn response = %{body: body} ->
          case opts |> Keyword.get(:xml_body_parser) do
            nil ->
              response

            xml_parser when is_function(xml_parser) ->
              response
              |> Map.merge(body |> xmap(xml_parser.()))
          end
        end).()
  end

  @response_headers [
    {"Date", :date, &DateTimeUtils.date_parse_rfc1123/1},
    {"Last-Modified", :last_modified, &DateTimeUtils.date_parse_rfc1123/1},
    {"Expires", :expires, &DateTimeUtils.date_parse_rfc1123/1},
    {"ETag", :etag},
    {"Content-MD5", :content_md5},
    {"x-ms-client-request-id", :x_ms_client_request_id},
    {"x-ms-request-id", :x_ms_request_id},
    {"x-ms-lease-state", :x_ms_lease_state},
    {"x-ms-blob-type", :x_ms_blob_type},
    {"x-ms-lease-status", :x_ms_lease_status},
    {"x-ms-request-server-encrypted", :x_ms_request_server_encrypted, &__MODULE__.to_bool/1},
    {"x-ms-delete-type-permanent", :x_ms_delete_type_permanent},
    {"x-ms-has-immutability-policy", :x_ms_has_immutability_policy, &__MODULE__.to_bool/1},
    {"x-ms-has-legal-hold", :x_ms_has_legal_hold, &__MODULE__.to_bool/1},
    {"x-ms-approximate-messages-count", :x_ms_approximate_messages_count,
     &__MODULE__.to_integer!/1},
    {"x-ms-error-code", :x_ms_error_code},
    {"x-ms-blob-public-access", :x_ms_blob_public_access, &Container.parse_access_level/1},
    {"x-ms-blob-cache-control", :x_ms_blob_cache_control},
    {"x-ms-cache-control", :x_ms_cache_control}
  ]

  defp copy_response_headers_into_map(response = %{}) do
    Enum.reduce(@response_headers, response, fn x, response ->
      response |> copy_response_header_into_map(x)
    end)
  end

  defp copy_response_header_into_map(response, {http_header, key_to_set}),
    do: response |> copy_response_header_into_map({http_header, key_to_set, &identity/1})

  defp copy_response_header_into_map(response, {http_header, key_to_set, transform})
       when is_map(response) and is_atom(key_to_set) and is_binary(http_header) and
              is_function(transform, 1) do
    http_header = http_header |> String.downcase()

    case get_header(response.headers, http_header) do
      nil -> response
      val -> response |> Map.put(key_to_set, val |> transform.())
    end
  end

  defp copy_x_ms_meta_headers_into_map(response) do
    x_ms_meta =
      response.headers
      |> Enum.filter(fn {k, _v} -> k |> String.starts_with?(@prefix_x_ms_meta) end)
      |> Enum.map(fn {@prefix_x_ms_meta <> k, v} -> {k, v} end)
      |> Enum.into(%{})

    case x_ms_meta |> Enum.empty?() do
      true -> response
      false -> response |> Map.put(:x_ms_meta, x_ms_meta)
    end
  end
end
