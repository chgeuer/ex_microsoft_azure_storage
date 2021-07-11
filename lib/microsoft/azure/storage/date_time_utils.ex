defmodule Microsoft.Azure.Storage.DateTimeUtils do
  use Timex

  def utc_now(),
    # https://docs.microsoft.com/en-us/rest/api/storageservices/representation-of-date-time-values-in-headers
    do:
      Timex.now()
      |> Timex.format!("{RFC1123z}")
      |> String.replace(" Z", " GMT")

  # "2019-02-05T16:43:10.4730000Z" |> Microsoft.Azure.Storage.DateTimeUtils.date_parse_iso8601()
  def date_parse_iso8601(date) do
    {:ok, result, 0} = date |> DateTime.from_iso8601()
    result
  end

  # Azure expects dates in YYYY-MM-DDThh:mm:ss.fffffffTZD,
  # where fffffff is the *seven*-digit millisecond representation.
  # &DateTime.to_iso8601/1 only generates six-digit millisecond
  def to_string_iso8601(date_time),
    do:
      date_time
      |> DateTime.to_iso8601()
      |> String.replace_trailing("Z", "0Z")

  # "Tue, 05 Feb 2019 16:58:12 GMT" |> Microsoft.Azure.Storage.DateTimeUtils.date_parse_rfc1123()
  def date_parse_rfc1123(str) do
    Timex.parse!(str, "{RFC1123}")
  end

  def to_string(timex_time),
    # https://docs.microsoft.com/en-us/rest/api/storageservices/representation-of-date-time-values-in-headers
    do:
      timex_time
      |> Timex.format!("{WDshort}, {0D} {Mshort} {YYYY} {0h24}:{0m}:{0s} GMT")
end
