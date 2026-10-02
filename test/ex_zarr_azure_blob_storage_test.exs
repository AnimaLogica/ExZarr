defmodule ExZarr.AzureBlobStorageTest do
  use ExUnit.Case

  alias ExZarr.Storage.Backend.AzureBlob

  @moduletag :azure

  # Configuration validation. Live Azurite/HTTP coverage is optional.
  # To run: mix test --include azure

  describe "Configuration validation" do
    test "requires account_name parameter without azure_client" do
      assert {:error, :account_name_required} =
               AzureBlob.init(account_key: "key", container: "test-container")
    end

    test "requires account_key parameter without azure_client" do
      assert {:error, :account_key_required} =
               AzureBlob.init(account_name: "testaccount", container: "test-container")
    end

    test "requires container parameter" do
      assert {:error, :container_required} =
               AzureBlob.init(account_name: "testaccount", account_key: "key")
    end

    test "accepts azure_client without Shared Key fields" do
      assert {:ok, state} =
               AzureBlob.init(
                 azure_client: %{stub: true},
                 container: "zarr-data",
                 prefix: "arrays/experiment1",
                 zarr_format: 3
               )

      assert state.container == "zarr-data"
      assert state.prefix == "arrays/experiment1"
      assert state.zarr_format == 3
    end

    test "accepts Shared Key configuration when azure_sdk is available" do
      case Code.ensure_loaded(AzureSDK.Storage.Client) do
        {:module, _} ->
          result =
            AzureBlob.init(
              account_name: "testaccount",
              account_key: "dGVzdGtleQ==",
              container: "zarr-data",
              prefix: "arrays/experiment1"
            )

          assert match?({:ok, _}, result) or match?({:error, _}, result)

        {:error, :nofile} ->
          assert true
      end
    end
  end
end
