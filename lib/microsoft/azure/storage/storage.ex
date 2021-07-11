defmodule Microsoft.Azure.Storage do
  @derive {Inspect, except: [:account_key]}
  @enforce_keys []
  defstruct account_name: nil,
            account_key: nil,
            host: nil,
            aad_token_provider: nil,
            cloud_environment_suffix: nil,
            is_development_factory: false

  @endpoint_names %{
    blob_service: "blob",
    queue_service: "queue",
    table_service: "table",
    file_service: "file"
  }

  @development_fabric_key "Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw=="

  @doc """
  Returns the storage context for the Azure storage emulator.
  """
  def development_factory(host \\ "127.0.0.1") do
    %__MODULE__{
      # https://docs.microsoft.com/en-us/azure/storage/common/storage-use-emulator#authenticating-requests-against-the-storage-emulator
      account_name: "devstoreaccount1",
      account_key: @development_fabric_key,
      host: host,
      is_development_factory: true
    }
  end

  def secondary(context = %__MODULE__{}),
    do:
      context
      |> Map.update!(:account_name, &(&1 <> "-secondary"))

  def endpoint_url(context = %__MODULE__{is_development_factory: true, host: host}, service)
      when is_atom(service) do
    port =
      case service do
        :blob_service -> 10000
        :queue_service -> 10001
        :table_service -> 10002
      end

    %URI{scheme: "http", host: host, port: port, path: "/" <> context.account_name}
    |> URI.to_string()
  end

  def endpoint_url(context = %__MODULE__{}, service) when is_atom(service),
    do: %URI{scheme: "https", host: endpoint_hostname(context, service)} |> URI.to_string()

  def endpoint_hostname(context = %__MODULE__{}, service) when is_atom(service),
    do: "#{context.account_name}.#{@endpoint_names[service]}.#{context.cloud_environment_suffix}"
end
