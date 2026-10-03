defmodule ExZarr.Storage.AzureAzuriteTest do
  use ExUnit.Case

  @moduletag :azure

  alias AzureSDK.Identity.SharedKeyCredential
  alias AzureSDK.Storage.{Client, Container}
  alias ExZarr.Storage.Backend.AzureBlob

  # Live Azurite coverage. Run with:
  #   AZURE_STORAGE_ACCOUNT=devstoreaccount1 \
  #   AZURE_STORAGE_KEY=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw== \
  #   AZURE_STORAGE_ENDPOINT=http://127.0.0.1:10000/devstoreaccount1 \
  #   mix test --include azure test/ex_zarr/storage/azure_azurite_test.exs

  @account System.get_env("AZURE_STORAGE_ACCOUNT")
  @key System.get_env("AZURE_STORAGE_KEY")
  @endpoint System.get_env("AZURE_STORAGE_ENDPOINT")
  @container System.get_env("TEST_AZURE_CONTAINER") || "exzarr-test"

  # Reported as skipped (not passed) when Azurite is not configured.
  if is_nil(@account) or is_nil(@key) or is_nil(@endpoint) do
    @moduletag skip: "set AZURE_STORAGE_ACCOUNT, AZURE_STORAGE_KEY and AZURE_STORAGE_ENDPOINT"
  end

  test "v3 keys and range read against Azurite" do
    assert Code.ensure_loaded?(Client)

    credential = SharedKeyCredential.new(@account, @key)

    client =
      Client.new(
        account: @account,
        credential: credential,
        endpoint: @endpoint
      )

    _ = Container.create(client, @container)

    prefix = "v3_range_#{System.unique_integer([:positive])}"

    {:ok, state} =
      AzureBlob.init(
        azure_client: client,
        container: @container,
        prefix: prefix,
        zarr_format: 3
      )

    data = <<1, 2, 3, 4, 5, 6, 7, 8>>
    assert :ok = AzureBlob.write_chunk(state, {0, 0}, data)
    assert {:ok, ^data} = AzureBlob.read_chunk(state, {0, 0})
    assert {:ok, <<3, 4>>} = AzureBlob.read_chunk_range(state, {0, 0}, 2, 2)

    assert {:ok, %{size: 8, etag: etag}} = AzureBlob.chunk_info(state, {0, 0})
    assert {:ok, <<3, 4>>} = AzureBlob.read_chunk_range(state, {0, 0}, 2, 2, if_match: etag)

    assert {:error, :precondition_failed} =
             AzureBlob.read_chunk_range(state, {0, 0}, 2, 2, if_match: ~s("0x0"))

    meta = Jason.encode!(%{zarr_format: 3, node_type: "array"})
    assert :ok = AzureBlob.write_metadata(state, meta, [])
    assert {:ok, _} = AzureBlob.read_metadata(state)
  end
end
