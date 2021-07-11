defmodule Microsoft.Azure.Storage.BlobPolicy do
  import SweetXml
  import Microsoft.Azure.Storage.DateTimeUtils
  import Microsoft.Azure.Storage.Utilities, only: [set_to_string: 2, string_to_set: 2]
  require EEx

  defstruct [:id, :start, :expiry, :permission]

  @perms %{read: "r", write: "w", delete: "d", list: "l"}

  def permission_serialize(permissions) when is_list(permissions),
    do: permissions |> set_to_string(@perms)

  def permission_parse(str) when is_binary(str),
    do: str |> string_to_set(@perms)

  def deserialize(xml_body) do
    xml_body
    |> xpath(~x"/SignedIdentifiers/SignedIdentifier"l)
    |> Enum.map(fn node ->
      %__MODULE__{
        id: node |> xpath(~x"./Id/text()"s),
        start:
          node |> xpath(~x"./AccessPolicy/Start/text()"s |> transform_by(&date_parse_iso8601/1)),
        expiry:
          node |> xpath(~x"./AccessPolicy/Expiry/text()"s |> transform_by(&date_parse_iso8601/1)),
        permission:
          node
          |> xpath(~x"./AccessPolicy/Permission/text()"s |> transform_by(&permission_parse/1))
      }
    end)
  end

  @template """
  <?xml version="1.0" encoding="utf-8"?>
  <SignedIdentifiers>
    <%= for policy <- @policies do %>
    <SignedIdentifier>
      <Id><%= policy.id %></Id>
      <AccessPolicy>
        <Start><%= policy.start |> Microsoft.Azure.Storage.DateTimeUtils.to_string_iso8601() %></Start>
        <Expiry><%= policy.expiry |> Microsoft.Azure.Storage.DateTimeUtils.to_string_iso8601() %></Expiry>
        <Permission><%= policy.permission |> Microsoft.Azure.Storage.BlobPolicy.permission_serialize() %></Permission>
      </AccessPolicy>Date
    </SignedIdentifier>
    <% end %>
  </SignedIdentifiers>
  """

  def serialize(policies) when is_list(policies),
    do: @template |> EEx.eval_string(assigns: [policies: policies]) |> Kernel.to_string()

  # def serialize(policies) when is_list(policies) do
  #   inner_xml =
  #     policies
  #     |> Enum.map(&serialize/1)
  #     |> Enum.join("")
  #
  #   bom = "\uFEFF"
  #
  #   bom <>
  #     "<?xml version=\"1.0\" encoding=\"utf-8\"?>" <>
  #     "<SignedIdentifiers>#{inner_xml}</SignedIdentifiers>"
  # end
  #
  # def serialize(policy = %__MODULE__{}) when is_map(policy),
  #   do:
  #     "<SignedIdentifier>" <>
  #       "<Id>#{policy.id}</Id>" <>
  #       "<AccessPolicy>" <>
  #       "<Start>#{policy.start |> DateTimeUtils.to_string_iso8601()}</Start>" <>
  #       "<Expiry>#{policy.expiry |> DateTimeUtils.to_string_iso8601()}</Expiry>" <>
  #       "<Permission>#{policy.permission |> permission_serialize()}</Permission>" <>
  #       "</AccessPolicy>" <> "</SignedIdentifier>"
end
