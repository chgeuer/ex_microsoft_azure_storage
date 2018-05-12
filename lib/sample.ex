defmodule Sample do
  use Timex
  alias Microsoft.Azure.Storage.{BlobStorage, BlobPolicy, AzureStorageContext, ContainerLease}

  def storage_context(),
    do: %AzureStorageContext{
      account_name: "SAMPLE_STORAGE_ACCOUNT_NAME" |> System.get_env(),
      account_key: "SAMPLE_STORAGE_ACCOUNT_KEY" |> System.get_env(),
      cloud_environment_suffix: "core.windows.net"
    }

  def list_containers(),
    do: storage_context() |> BlobStorage.list_containers()

  def get_blob_service_stats(),
    do: storage_context() |> BlobStorage.get_blob_service_stats()

  def create_container(container_name),
    do: storage_context() |> BlobStorage.create_container(container_name)

  def delete_container(container_name),
    do: storage_context() |> BlobStorage.delete_container(container_name)

  def list_blobs(container_name, opts \\ []),
    do: storage_context() |> BlobStorage.list_blobs(container_name, opts)

  def get_container_properties(container_name),
    do: storage_context() |> BlobStorage.get_container_properties(container_name)

  def get_container_metadata(container_name),
    do: storage_context() |> BlobStorage.get_container_metadata(container_name)

  def get_container_acl(container_name),
    do: storage_context() |> BlobStorage.get_container_acl(container_name)

  def set_container_acl_public_access_off(container_name),
    do: storage_context() |> BlobStorage.set_container_acl_public_access_off(container_name)

  def set_container_acl_public_access_blob(container_name),
    do: storage_context() |> BlobStorage.set_container_acl_public_access_blob(container_name)

  def set_container_acl_public_access_container(container_name),
    do: storage_context() |> BlobStorage.set_container_acl_public_access_container(container_name)

  def set_container_acl(container_name),
    do:
      storage_context()
      |> BlobStorage.set_container_acl(container_name, [
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
    |> ContainerLease.container_lease_acquire(
      container_name,
      lease_duration,
      "00000000-1111-2222-3333-444444444444"
    )
    |> IO.inspect()

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
    |> ContainerLease.container_lease_acquire(
      container_name,
      lease_duration,
      "00000000-1111-2222-3333-444444444444"
    )
    |> IO.inspect()

    0..3
    |> Enum.each(fn i ->
      Process.sleep(200)

      {:ok, %{lease_state: lease_state, lease_status: lease_status}} =
        get_container_properties(container_name)

      IO.puts("#{i}: lease_state=#{lease_state} lease_status=#{lease_status}")
    end)

    IO.puts("Call release now")

    storage_context()
    |> ContainerLease.container_lease_release(
      container_name,
      "00000000-1111-2222-3333-444444444444"
    )
    |> IO.inspect()

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
      |> ContainerLease.container_lease_acquire(
        container_name,
        lease_duration,
        "00000000-1111-2222-3333-444444444444"
      )
      |> IO.inspect()

    IO.puts("Acquired lease #{lease_id}")

    0..lease_duration
    |> Enum.each(fn _ ->
      Process.sleep(1000)

      storage_context()
      |> ContainerLease.container_lease_renew(container_name, lease_id)
      |> IO.inspect()
    end)
  end

  def container_lease_break(container_name) do
    lease_duration = 60

    {:ok,
     %{
       lease_id: lease_id
     }} =
      storage_context()
      |> ContainerLease.container_lease_acquire(
        container_name,
        lease_duration,
        "00000000-1111-2222-3333-444444444444"
      )
      |> IO.inspect()

    IO.puts("Acquired lease #{lease_id}")

    Process.sleep(1000)

    break_period = 5

    storage_context()
    |> ContainerLease.container_lease_break(container_name, lease_id, break_period)
    |> IO.inspect()
  end

  def container_lease_acquire_and_change(container_name) do
    lease_duration = 60

    storage_context()
    |> ContainerLease.container_lease_acquire(
      container_name,
      lease_duration,
      "00000000-1111-2222-3333-444444444444"
    )
    |> IO.inspect()

    Process.sleep(1000)

    IO.puts("Change to new lease ID ")

    storage_context()
    |> ContainerLease.container_lease_change(
      container_name,
      "00000000-1111-2222-3333-444444444444",
      "00000000-1111-2222-3333-555555555555"
    )
  end
end