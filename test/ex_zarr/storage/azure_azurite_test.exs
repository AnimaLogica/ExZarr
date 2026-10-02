defmodule ExZarr.Storage.AzureAzuriteTest do
  use ExUnit.Case

  @moduletag :azure

  # Live Azurite coverage. Run with:
  #   AZURE_STORAGE_ACCOUNT=devstoreaccount1 \
  #   AZURE_STORAGE_KEY=Eby8vdM02xNOcqFlqUwJPLlmEtlCDXJ1OUzFT50uSRZ6IFsuFq2UVErCz4I6tq/K1SZFPTOtr/KBHBeksoGMGw== \
  #   AZURE_STORAGE_ENDPOINT=http://127.0.0.1:10000/devstoreaccount1 \
  #   mix test --include azure test/ex_zarr/storage/azure_azurite_test.exs

  @account System.get_env("AZURE_STORAGE_ACCOUNT")
  @key System.get_env("AZURE_STORAGE_KEY")
  @endpoint System.get_env("AZURE_STORAGE_ENDPOINT")
  @container System.get_env("TEST_AZURE_CONTAINER") || "exzarr-test"

  setup do
    if is_nil(@account) or is_nil(@key) or is_nil(@endpoint) do
      {:ok, skip: true}
    else
      {:ok, skip: false}
    end
  end

  test "v3 keys and range read against Azurite", %{skip: skip} do
    if skip do
      assert true
    else
      alias ExZarr.Storage.Backend.AzureBlob

      assert Code.ensure_loaded?(AzureSDK.Storage.Client)

      credential = AzureSDK.Identity.SharedKeyCredential.new(@account, @key)

      client =
        AzureSDK.Storage.Client.new(
          account: @account,
          credential: credential,
          endpoint: @endpoint
        )

      _ = AzureSDK.Storage.Container.create(client, @container)

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

      meta = Jason.encode!(%{zarr_format: 3, node_type: "array"})
      assert :ok = AzureBlob.write_metadata(state, meta, [])
      assert {:ok, _} = AzureBlob.read_metadata(state)
    end
  end
end
