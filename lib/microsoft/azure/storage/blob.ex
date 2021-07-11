defmodule Microsoft.Azure.Storage.Blob do
  require Logger
  import SweetXml
  use NamedArgs
  # import SweetXml
  import Microsoft.Azure.Storage.RequestBuilder
  alias Microsoft.Azure.Storage.{Container}

  @enforce_keys [:container, :blob_name]
  @max_concurrency 3
  @max_number_of_blocks 50_000
  @mega_byte 1024 * 1024
  @max_block_size 4 * @mega_byte
  @max_block_size_100MB 100 * @mega_byte

  defstruct [:container, :blob_name]

  def new(container = %Container{}, blob_name)
      when is_binary(blob_name),
      do: %__MODULE__{container: container, blob_name: blob_name}

  def to_block_id(block_id) when is_binary(block_id), do: block_id
  def to_block_id(block_id) when is_integer(block_id), do: <<block_id::120>> |> Base.encode64()

  @doc """
  The `put_block` operation creates a new block to be committed as part of a blob.
  """
  def put_block(
        %__MODULE__{
          container: %Container{storage_context: context, container_name: container_name},
          blob_name: blob_name
        },
        block_id,
        content
      )
      when is_binary(block_id) and byte_size(content) <= @max_block_size_100MB do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/put-block

    response =
      context
      |> new_azure_storage_request()
      |> method(:put)
      |> url("/#{container_name}/#{blob_name}")
      |> add_param(:query, :comp, "block")
      # |> to_block_id())
      |> add_param(:query, :blockid, block_id)
      |> body(content)
      |> add_header_content_md5()
      |> sign_and_call(:blob_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        {:error, response |> create_error_response()}

      %{status: 201} ->
        {:ok,
         response
         |> create_success_response()}
    end
  end

  @doc """
  The `put_block_list` operation writes a blob by specifying the list of block IDs that make up the blob.
  """
  def put_block_list(
        %__MODULE__{
          container: %Container{storage_context: context, container_name: container_name},
          blob_name: blob_name
        },
        block_list
      )
      when is_list(block_list) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/put-block-list
    response =
      context
      |> new_azure_storage_request()
      |> method(:put)
      |> url("/#{container_name}/#{blob_name}")
      |> add_param(:query, :comp, "blocklist")
      |> body(block_list |> serialize_block_list())
      |> sign_and_call(:blob_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        {:error, response |> create_error_response()}

      %{status: 201} ->
        {:ok,
         response
         |> create_success_response()}
    end
  end

  @template_block_list """
  <?xml version="1.0" encoding="utf-8"?>
  <BlockList>
    <%= for block <- @block_list do %>
    <Latest><%= block |> Microsoft.Azure.Storage.Blob.to_block_id() %></Latest>
    <% end %>
  </BlockList>
  """

  defp serialize_block_list(block_list),
    do: @template_block_list |> EEx.eval_string(assigns: [block_list: block_list]) |> to_string()

  defp deserialize_block_list(xml_body) do
    deserialize_block = fn node ->
      %{
        name: node |> xpath(~x"./Name/text()"s),
        size:
          node
          |> xpath(
            ~x"./Size/text()"s
            |> transform_by(fn t -> t |> Integer.parse() |> elem(0) end)
          )
      }
    end

    %{
      committed_blocks:
        xml_body
        |> xpath(~x"/BlockList/CommittedBlocks/Block"l)
        |> Enum.map(deserialize_block),
      uncommitted_blocks:
        xml_body
        |> xpath(~x"/BlockList/UncommittedBlocks/Block"l)
        |> Enum.map(deserialize_block)
    }
  end

  def get_block_list(
        %__MODULE__{
          container: %Container{storage_context: context, container_name: container_name},
          blob_name: blob_name
        },
        block_list_type \\ :all,
        snapshot \\ nil
      )
      when block_list_type in [:all, :committed, :uncommitted] do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/get-block-list

    response =
      context
      |> new_azure_storage_request()
      |> method(:get)
      |> url("/#{container_name}/#{blob_name}")
      |> add_param(:query, :comp, "blocklist")
      |> add_param(:query, :blocklisttype, block_list_type |> Atom.to_string())
      |> add_param_if(snapshot != nil, :query, :snapshot, snapshot)
      |> sign_and_call(:blob_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        {:error, response |> create_error_response()}

      %{status: 200} ->
        {:ok,
         response
         |> create_success_response()
         |> Map.merge(response.body |> deserialize_block_list())}
    end
  end

  @spec upload_file(Container.t(), String.t()) :: {:ok, map} | {:error, map}
  def upload_file(container = %Container{}, source_path, blob_name \\ nil) do
    container
    |> to_blob(source_path, blob_name)
    |> upload_async(source_path)
  end

  defp to_blob(container, source_path, nil) do
    target_filename =
      source_path
      |> Path.basename()
      |> URI.encode()

    to_blob(container, source_path, target_filename)
  end

  defp to_blob(container, _source_filename, target_filename) do
    __MODULE__.new(container, target_filename)
  end

  defp upload_async(blob, filename) do
    blob
    |> upload_stream(filename)
    |> stream_to_block_ids()
    |> case do
      {:error, _reason} = err ->
        err
      {:ok, ids} ->
        commit_block_ids(blob, ids)
    end
  end

  defp upload_stream(blob, filename) do
    filename
    |> File.stream!([], @max_block_size)
    |> Stream.zip(1..@max_number_of_blocks)
    |> Task.async_stream(
      fn {content, i} ->
        block_id = to_block_id(i)

        case put_block(blob, block_id, content) do
          {:ok, _} ->
            block_id

          {:error, _resp} = error ->
            error
        end
      end,
      max_concurrency: @max_concurrency,
      ordered: true,
      timeout: :infinity
    )
    |> Enum.to_list()
  end

  defp stream_to_block_ids(results) do
    Enum.reduce_while(results, {:ok, []}, fn
      {_, {:error, reason}}, {_status, _ids} ->
        {:halt, {:error, reason}}

      {_, id}, {status, ids} ->
        {:cont, {status, [id | ids]}}
    end)
  end

  defp commit_block_ids(blob, ids) do
    block_ids =
      1..@max_number_of_blocks
      |> Enum.map(&to_block_id/1)
      |> Enum.filter(&(&1 in ids))

    put_block_list(blob, block_ids)
  end

  def delete_blob(
        %__MODULE__{
          container: %Container{storage_context: context, container_name: container_name},
          blob_name: blob_name
        },
        opts \\ []
      ) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/delete-blob

    %{snapshot: snapshot, timeout: timeout} =
      case [snapshot: nil, timeout: -1]
           |> Keyword.merge(opts)
           |> Enum.into(%{}) do
        %{snapshot: snapshot, timeout: timeout} -> %{snapshot: snapshot, timeout: timeout}
      end

    response =
      context
      |> new_azure_storage_request()
      |> method(:delete)
      |> url("/#{container_name}/#{blob_name}")
      |> add_param_if(snapshot != nil, :query, :snapshot, snapshot)
      |> add_param_if(timeout > 0, :query, :timeout, timeout)
      |> sign_and_call(:blob_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        {:error, response |> create_error_response()}

      %{status: 202} ->
        {:ok, response |> create_success_response()}
    end
  end
end
