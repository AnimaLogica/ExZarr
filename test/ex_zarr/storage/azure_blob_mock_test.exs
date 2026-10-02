defmodule ExZarr.Storage.AzureBlobMockTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.Backend.AzureBlob

  defmodule MockBlob do
    def download(_client, _container, blob_name, opts \\ []) do
      send(self(), {:azure_download, blob_name, opts})

      cond do
        String.ends_with?(blob_name, ".zarray") or String.ends_with?(blob_name, "zarr.json") ->
          {:ok, %{content: mock_metadata_json(blob_name), properties: %{}}}

        String.match?(blob_name, ~r/(^|\/)c\//) or
            String.match?(blob_name, ~r/^(.*\/)?\d+(\.\d+)*$/) ->
          # Treat very high indices as missing for not_found tests
          case Regex.run(
                 ~r/(\d+)(?:\.|$)/,
                 Path.basename(blob_name) |> String.replace_prefix("c/", "")
               ) do
            [_, n] ->
              if String.to_integer(n) >= 99 do
                {:error, %{status: 404, message: "Not Found"}}
              else
                case Keyword.get(opts, :range) do
                  {start, finish} ->
                    data = <<1, 2, 3, 4, 5, 6, 7, 8>>

                    {:ok,
                     %{content: binary_part(data, start, finish - start + 1), properties: %{}}}

                  nil ->
                    {:ok, %{content: <<1, 2, 3, 4, 5>>, properties: %{}}}
                end
              end

            _ ->
              {:ok, %{content: <<1, 2, 3, 4, 5>>, properties: %{}}}
          end

        true ->
          {:error, %{status: 404, message: "Not Found"}}
      end
    end

    def upload(_client, _container, blob_name, data, _opts \\ []) do
      send(self(), {:azure_upload, blob_name, data})
      {:ok, %{content: data, properties: %{}}}
    end

    def delete(_client, _container, blob_name, _opts \\ []) do
      send(self(), {:azure_delete, blob_name})
      {:ok, :deleted}
    end

    def properties(_client, _container, blob_name, _opts \\ []) do
      send(self(), {:azure_properties, blob_name})

      {:ok,
       %{
         content_length: 8,
         etag: "\"etag1\"",
         content_type: nil,
         last_modified: nil,
         metadata: %{}
       }}
    end

    defp mock_metadata_json(name) do
      format = if String.ends_with?(name, "zarr.json"), do: 3, else: 2

      Jason.encode!(%{
        zarr_format: format,
        shape: [100, 100],
        chunks: [10, 10],
        dtype: "<f8",
        compressor: nil,
        fill_value: 0,
        order: "C",
        filters: nil
      })
    end
  end

  defmodule MockContainer do
    def list_blobs(_client, _container, opts \\ []) do
      prefix = Keyword.get(opts, :prefix, "")
      send(self(), {:azure_list, prefix})

      items =
        case prefix do
          "" ->
            [%{name: ".zarray"}, %{name: "0.0"}, %{name: "0.1"}, %{name: "1.0"}]

          "v3/" ->
            [%{name: "v3/zarr.json"}, %{name: "v3/c/0/0"}, %{name: "v3/c/0/1"}]

          _ ->
            [%{name: "#{prefix}.zarray"}, %{name: "#{prefix}0.0"}, %{name: "#{prefix}0.1"}]
        end

      {:ok, items}
    end

    def exists?(_client, _container, _opts \\ []), do: true
  end

  defmodule MockIdentity do
    def new(account, key), do: %{account: account, key: key}
  end

  defmodule MockStorageClient do
    def new(opts), do: %{opts: opts}
  end

  setup do
    Application.put_env(:ex_zarr, :azure_blob_module, MockBlob)
    Application.put_env(:ex_zarr, :azure_container_module, MockContainer)
    Application.put_env(:ex_zarr, :azure_identity_module, MockIdentity)
    Application.put_env(:ex_zarr, :azure_storage_client_module, MockStorageClient)

    on_exit(fn ->
      Application.delete_env(:ex_zarr, :azure_blob_module)
      Application.delete_env(:ex_zarr, :azure_container_module)
      Application.delete_env(:ex_zarr, :azure_identity_module)
      Application.delete_env(:ex_zarr, :azure_storage_client_module)
    end)

    :ok
  end

  defp base_config(opts \\ []) do
    [
      account_name: "myaccount",
      account_key: "mykey",
      container: "test-container"
    ]
    |> Keyword.merge(opts)
  end

  describe "backend_id/0" do
    test "returns :azure_blob" do
      assert AzureBlob.backend_id() == :azure_blob
    end
  end

  describe "init/1" do
    test "initializes with Shared Key fields" do
      assert {:ok, state} = AzureBlob.init(base_config(prefix: "data"))
      assert state.container == "test-container"
      assert state.prefix == "data"
      assert state.zarr_format == 2

      assert state.client == %{
               opts: [account: "myaccount", credential: %{account: "myaccount", key: "mykey"}]
             }
    end

    test "accepts prebuilt azure_client without account credentials" do
      client = %{prebuilt: true}

      assert {:ok, state} =
               AzureBlob.init(
                 azure_client: client,
                 container: "c1",
                 prefix: "p",
                 zarr_format: 3
               )

      assert state.client == client
      assert state.zarr_format == 3
    end

    test "returns error for missing container" do
      assert {:error, :container_required} =
               AzureBlob.init(account_name: "a", account_key: "k")
    end

    test "returns error for missing Shared Key when no azure_client" do
      assert {:error, :account_name_required} =
               AzureBlob.init(account_key: "k", container: "c")

      assert {:error, :account_key_required} =
               AzureBlob.init(account_name: "a", container: "c")
    end
  end

  describe "v2 object naming" do
    test "reads and writes v2 chunk and metadata keys" do
      {:ok, state} = AzureBlob.init(base_config())

      assert {:ok, _} = AzureBlob.read_chunk(state, {0, 0})
      assert_receive {:azure_download, "0.0", _}

      assert :ok = AzureBlob.write_chunk(state, {1, 2, 3}, <<9>>)
      assert_receive {:azure_upload, "1.2.3", <<9>>}

      assert {:ok, _} = AzureBlob.read_metadata(state)
      assert_receive {:azure_download, ".zarray", _}
    end
  end

  describe "v3 object naming" do
    test "reads and writes v3 chunk and metadata keys" do
      {:ok, state} = AzureBlob.init(base_config(zarr_format: 3, prefix: "arrays/exp"))

      assert {:ok, _} = AzureBlob.read_chunk(state, {0, 1})
      assert_receive {:azure_download, "arrays/exp/c/0/1", _}

      assert :ok = AzureBlob.write_chunk(state, {2, 3}, <<1, 2>>)
      assert_receive {:azure_upload, "arrays/exp/c/2/3", <<1, 2>>}

      assert {:ok, _} = AzureBlob.read_metadata(state)
      assert_receive {:azure_download, "arrays/exp/zarr.json", _}
    end

    test "write_metadata uses zarr_format from JSON body" do
      {:ok, state} = AzureBlob.init(base_config(zarr_format: 2))
      meta = Jason.encode!(%{zarr_format: 3, node_type: "array"})
      assert :ok = AzureBlob.write_metadata(state, meta, [])
      assert_receive {:azure_upload, "zarr.json", ^meta}
    end
  end

  describe "list_chunks/1" do
    test "lists v2 chunks" do
      {:ok, state} = AzureBlob.init(base_config())
      assert {:ok, chunks} = AzureBlob.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}]
    end

    test "lists v3 chunks" do
      {:ok, state} = AzureBlob.init(base_config(prefix: "v3", zarr_format: 3))
      assert {:ok, chunks} = AzureBlob.list_chunks(state)
      assert Enum.sort(chunks) == [{0, 0}, {0, 1}]
    end
  end

  describe "range helpers" do
    test "chunk_info and read_chunk_range" do
      {:ok, state} = AzureBlob.init(base_config())
      assert {:ok, %{size: 8, etag: "\"etag1\""}} = AzureBlob.chunk_info(state, {0, 0})
      assert {:ok, <<3, 4>>} = AzureBlob.read_chunk_range(state, {0, 0}, 2, 2)
      assert_receive {:azure_download, "0.0", opts}
      assert Keyword.get(opts, :range) == {2, 3}
      assert Keyword.get(opts, :if_match) == "\"etag1\""
    end

    test "capabilities includes range_read" do
      {:ok, state} = AzureBlob.init(base_config())
      assert MapSet.member?(AzureBlob.capabilities(state), :range_read)
    end
  end

  describe "error normalization" do
    test "404 becomes :not_found" do
      {:ok, state} = AzureBlob.init(base_config())
      assert {:error, :not_found} = AzureBlob.read_chunk(state, {99, 99})
    end
  end
end
