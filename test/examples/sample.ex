defmodule Sample do
  use Timex

  alias Microsoft.Azure.Storage
  alias Microsoft.Azure.Storage.{BlobStorage, BlobPolicy, Container, ContainerLease, Blob}

  import XmlBuilder
  import Microsoft.Azure.Storage.SharedAccessSignature

  def person(id, first, last) do
    element(:person, %{id: id}, [
      element(:first, first),
      element(:last, last)
    ])
  end

  def storage_context(),
    do: %Storage{
      account_name: "SAMPLE_STORAGE_ACCOUNT_NAME" |> System.get_env(),
      account_key: "SAMPLE_STORAGE_ACCOUNT_KEY" |> System.get_env(),
      cloud_environment_suffix: "core.windows.net"
    }

  def upload() do
    filename = "C:/Users/chgeuer/Desktop/Konstantin/VID_20181213_141227.mp4"
    # ""../../../Users/chgeuer/Videos/outbreak.mp4"

    container =
      storage_context()
      |> Container.new("videos")

    container
    |> Container.create_container()

    container
    |> Blob.upload_file(filename)
  end

  def get_blob_service_properties(),
    do: storage_context() |> BlobStorage.get_blob_service_properties()

  def re_set_blob_service_properties() do
    props =
      storage_context()
      |> BlobStorage.get_blob_service_properties()
      |> elem(1)
      |> Map.get(:service_properties)

    storage_context()
    |> BlobStorage.set_blob_service_properties(props)
  end

  def list_containers(),
    do:
      storage_context()
      |> Container.list_containers()

  def get_blob_service_stats(),
    do: storage_context() |> BlobStorage.get_blob_service_stats()

  def create_container(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.create_container()

  def delete_container(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.delete_container()

  def list_blobs(container_name, opts \\ []),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.list_blobs(opts)

  def get_container_properties(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.get_container_properties()

  def get_container_metadata(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.get_container_metadata()

  def get_container_acl(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.get_container_acl()

  def set_container_acl_public_access_off(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.set_container_acl_public_access_off()

  def set_container_acl_public_access_blob(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.set_container_acl_public_access_blob()

  def set_container_acl_public_access_container(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.set_container_acl_public_access_container()

  def set_container_acl(container_name),
    do:
      storage_context()
      |> Container.new(container_name)
      |> Container.set_container_acl([
        %BlobPolicy{
          id: "pol1",
          start: Timex.now() |> Timex.shift(minutes: -10),
          expiry: Timex.now() |> Timex.shift(years: 1),
          permission: [:list]
        }
      ])

  def container_lease_acquire(container_name) do
    lease_duration = 16

    storage_context()
    |> Container.new(container_name)
    |> ContainerLease.container_lease_acquire(
      lease_duration,
      "00000000-1111-2222-3333-444444444444"
    )

    0..lease_duration
    |> Enum.each(fn i ->
      Process.sleep(1000)

      {:ok, %{lease_state: lease_state, lease_status: lease_status}} =
        get_container_properties(container_name)

      IO.puts("#{i}: lease_state=#{lease_state} lease_status=#{lease_status}")
    end)
  end

  def container_lease_release(container_name) do
    lease_duration = 60

    storage_context()
    |> Container.new(container_name)
    |> ContainerLease.container_lease_acquire(
      lease_duration,
      "00000000-1111-2222-3333-444444444444"
    )

    0..3
    |> Enum.each(fn i ->
      Process.sleep(200)

      {:ok, %{lease_state: lease_state, lease_status: lease_status}} =
        get_container_properties(container_name)

      IO.puts("#{i}: lease_state=#{lease_state} lease_status=#{lease_status}")
    end)

    IO.puts("Call release now")

    storage_context()
    |> Container.new(container_name)
    |> ContainerLease.container_lease_release("00000000-1111-2222-3333-444444444444")

    0..3
    |> Enum.each(fn i ->
      Process.sleep(200)

      {:ok, %{lease_state: lease_state, lease_status: lease_status}} =
        get_container_properties(container_name)

      IO.puts("#{i}: lease_state=#{lease_state} lease_status=#{lease_status}")
    end)
  end

  def container_lease_renew(container_name) do
    lease_duration = 16

    {:ok,
     %{
       lease_id: lease_id
     }} =
      storage_context()
      |> Container.new(container_name)
      |> ContainerLease.container_lease_acquire(
        lease_duration,
        "00000000-1111-2222-3333-444444444444"
      )

    IO.puts("Acquired lease #{lease_id}")

    0..lease_duration
    |> Enum.each(fn _ ->
      Process.sleep(1000)

      storage_context()
      |> Container.new(container_name)
      |> ContainerLease.container_lease_renew(lease_id)
    end)
  end

  def container_lease_break(container_name) do
    lease_duration = 60

    {:ok,
     %{
       lease_id: lease_id
     }} =
      storage_context()
      |> Container.new(container_name)
      |> ContainerLease.container_lease_acquire(
        lease_duration,
        "00000000-1111-2222-3333-444444444444"
      )

    IO.puts("Acquired lease #{lease_id}")

    Process.sleep(1000)

    break_period = 5

    storage_context()
    |> Container.new(container_name)
    |> ContainerLease.container_lease_break(lease_id, break_period)
  end

  def container_lease_acquire_and_change(container_name) do
    lease_duration = 60

    storage_context()
    |> Container.new(container_name)
    |> ContainerLease.container_lease_acquire(
      lease_duration,
      "00000000-1111-2222-3333-444444444444"
    )

    Process.sleep(1000)

    IO.puts("Change to new lease ID ")

    storage_context()
    |> Container.new(container_name)
    |> ContainerLease.container_lease_change(
      "00000000-1111-2222-3333-444444444444",
      "00000000-1111-2222-3333-555555555555"
    )
  end

  def sas1() do
    new()
    |> for_storage_account()
    |> add_service_table()
    |> add_service_queue()
    |> add_service_queue()
    |> add_service_queue()
    |> add_resource_type_service()
    |> add_resource_type_object()
    |> add_permission_read()
    |> ip_range("168.1.5.60-168.1.5.70")
    # |> for_blob_service()
    |> start_time(Timex.now())
    |> expiry_time(Timex.now() |> Timex.add(Timex.Duration.from_hours(1)))
    |> protocol("https")
  end

  def demo() do
    sas1()
    |> sign(%Storage{
      cloud_environment_suffix: "core.windows.net",
      account_name: "SAMPLE_STORAGE_ACCOUNT_NAME" |> System.get_env(),
      account_key: "SAMPLE_STORAGE_ACCOUNT_KEY" |> System.get_env()
    })
    |> URI.decode_query()
  end

  def d2() do
    new()
    |> service_version(ApiVersion.get_api_version(:storage))
    |> for_storage_account()
    |> add_service_blob()
    |> add_resource_type_container()
    |> add_resource_blob_container()
    |> add_permission_read()
    |> add_permission_process()
    |> add_permission_list()
    |> start_time(Timex.now())
    |> expiry_time(
      Timex.now()
      |> Timex.add(Timex.Duration.from_days(100))
    )
    |> sign(%Storage{
      cloud_environment_suffix: "core.windows.net",
      account_name: "SAMPLE_STORAGE_ACCOUNT_NAME" |> System.get_env(),
      account_key: "SAMPLE_STORAGE_ACCOUNT_KEY" |> System.get_env()
    })
  end
end
