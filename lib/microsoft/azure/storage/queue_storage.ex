defmodule Microsoft.Azure.Storage.QueueStorage do
  use NamedArgs
  use Timex
  import SweetXml
  import Microsoft.Azure.Storage.RequestBuilder
  alias Microsoft.Azure.Storage.DateTimeUtils
  alias Microsoft.Azure.Storage.AzureStorageContext.Queue

  def create_queue(%Queue{storage_context: context, queue_name: queue_name}) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/create-queue4
    response =
      new_azure_storage_request()
      |> method(:put)
      |> url("/#{queue_name}")
      |> add_ms_context(context, DateTimeUtils.utc_now(), :storage)
      |> sign_and_call(:queue_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        response |> create_error_response()

      %{status: 201} ->
        {:ok,
         %{
           headers: response.headers,
           url: response.url,
           status: response.status,
           request_id: response.headers["x-ms-request-id"],
           etag: response.headers["etag"],
           last_modified: response.headers["last-modified"]
         }}
    end
  end

  @seconds_7_days 7 * 24 * 60 * 60

  def put_message(
        %Queue{storage_context: context, queue_name: queue_name},
        message,
        opts \\ []
      )
      when is_binary(message) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/put-message

    %{
      visibilitytimeout: visibilitytimeout,
      messagettl: messagettl
    } =
      case [visibilitytimeout: 0, messagettl: 0]
           |> Keyword.merge(opts)
           |> Enum.into(%{}) do
        %{
          visibilitytimeout: visibilitytimeout,
          messagettl: messagettl
        }
        when visibilitytimeout >= 0 and visibilitytimeout <= @seconds_7_days and
               (messagettl == -1 or messagettl == 0 or
                  (messagettl >= 1 and messagettl <= @seconds_7_days)) ->
          %{
            visibilitytimeout: visibilitytimeout,
            messagettl: messagettl
          }
      end

    body = "<QueueMessage><MessageText>#{message |> Base.encode64()}</MessageText></QueueMessage>"

    response =
      new_azure_storage_request()
      |> method(:post)
      |> url("/#{queue_name}/messages")
      |> add_param_if(visibilitytimeout > 0, :query, :visibilitytimeout, visibilitytimeout)
      |> add_param_if(messagettl != 0, :query, :messagettl, messagettl)
      |> add_ms_context(context, DateTimeUtils.utc_now(), :storage)
      |> body(body)
      |> sign_and_call(:queue_service)

    date_parse = &(&1 |> Timex.parse!("{RFC1123}"))

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        response |> create_error_response()

      %{status: 201} ->
        {:ok,
         response.body
         |> xmap(
           message_id: ~x"/QueueMessagesList/QueueMessage/MessageId/text()"s,
           pop_receipt: ~x"/QueueMessagesList/QueueMessage/PopReceipt/text()"s,
           insertion_time:
             ~x"/QueueMessagesList/QueueMessage/InsertionTime/text()"s |> transform_by(date_parse),
           expiration_time:
             ~x"/QueueMessagesList/QueueMessage/ExpirationTime/text()"s
             |> transform_by(date_parse),
           time_next_visible:
             ~x"/QueueMessagesList/QueueMessage/TimeNextVisible/text()"s
             |> transform_by(date_parse)
         )
         |> Map.put(:headers, response.headers)
         |> Map.put(:url, response.url)
         |> Map.put(:status, response.status)
         |> Map.put(:request_id, response.headers["x-ms-request-id"])}
    end
  end

  def get_message(%Queue{storage_context: context, queue_name: queue_name}, opts \\ []) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/get-message

    %{
      numofmessages: numofmessages,
      visibilitytimeout: visibilitytimeout,
      timeout: timeout
    } =
      case [numofmessages: 1, visibilitytimeout: 0, timeout: 0]
           |> Keyword.merge(opts)
           |> Enum.into(%{}) do
        %{
          numofmessages: numofmessages,
          visibilitytimeout: visibilitytimeout,
          timeout: timeout
        }
        when is_integer(numofmessages) and numofmessages >= 1 and numofmessages <= 32 and
               visibilitytimeout > 1 and visibilitytimeout <= @seconds_7_days ->
          %{
            numofmessages: numofmessages,
            visibilitytimeout: visibilitytimeout,
            timeout: timeout
          }
      end

    response =
      new_azure_storage_request()
      |> method(:get)
      |> url("/#{queue_name}/messages")
      |> add_param(:query, :numofmessages, numofmessages)
      |> add_param(:query, :visibilitytimeout, visibilitytimeout)
      |> add_param(:query, :timeout, timeout)
      |> add_ms_context(context, DateTimeUtils.utc_now(), :storage)
      |> sign_and_call(:queue_service)

    date_parse = &(&1 |> Timex.parse!("{RFC1123}"))

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        response |> create_error_response()

      %{status: 200} ->
        {:ok,
         response.body
         |> xmap(
           message_id: ~x"/QueueMessagesList/QueueMessage/MessageId/text()"s,
           pop_receipt: ~x"/QueueMessagesList/QueueMessage/PopReceipt/text()"s,
           insertion_time:
             ~x"/QueueMessagesList/QueueMessage/InsertionTime/text()"s |> transform_by(date_parse),
           expiration_time:
             ~x"/QueueMessagesList/QueueMessage/ExpirationTime/text()"s
             |> transform_by(date_parse),
           time_next_visible:
             ~x"/QueueMessagesList/QueueMessage/TimeNextVisible/text()"s
             |> transform_by(date_parse),
           dequeue_count: ~x"/QueueMessagesList/QueueMessage/DequeueCount/text()"s,
           message_text:
             ~x"/QueueMessagesList/QueueMessage/MessageText/text()"s
             |> transform_by(&Base.decode64!/1)
         )
         |> Map.put(:headers, response.headers)
         |> Map.put(:url, response.url)
         |> Map.put(:status, response.status)
         |> Map.put(:request_id, response.headers["x-ms-request-id"])}
    end
  end

  def delete_message(
        %Queue{storage_context: context, queue_name: queue_name},
        popreceipt,
        timeout \\ 30
      ) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/delete-message2

    response =
      new_azure_storage_request()
      |> method(:delete)
      |> url("/#{queue_name}/messages/messageid")
      |> add_param(:query, :popreceipt, popreceipt)
      |> add_param(:query, :timeout, timeout)
      |> add_ms_context(context, DateTimeUtils.utc_now(), :storage)
      |> sign_and_call(:queue_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        response |> create_error_response()

      %{status: 204} ->
        {:ok,
         %{
           headers: response.headers,
           url: response.url,
           status: response.status,
           request_id: response.headers["x-ms-request-id"]
         }}
    end
  end

  def clear_messages(
        %Queue{storage_context: context, queue_name: queue_name},
        timeout \\ 30
      ) do
    # https://docs.microsoft.com/en-us/rest/api/storageservices/clear-messages

    response =
      new_azure_storage_request()
      |> method(:delete)
      |> url("/#{queue_name}/messages")
      |> add_param(:query, :timeout, timeout)
      |> add_ms_context(context, DateTimeUtils.utc_now(), :storage)
      |> sign_and_call(:queue_service)

    case response do
      %{status: status} when 400 <= status and status < 500 ->
        response |> create_error_response()

      %{status: 204} ->
        {:ok,
         %{
           headers: response.headers,
           url: response.url,
           status: response.status,
           request_id: response.headers["x-ms-request-id"]
         }}
    end
  end
end