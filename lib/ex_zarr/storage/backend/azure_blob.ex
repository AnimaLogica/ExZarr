defmodule ExZarr.Storage.Backend.AzureBlob do
  @moduledoc """
  Azure Blob Storage backend for Zarr arrays.

  Uses optional `azure_sdk` (`~> 0.4.1`). Arrays may be stored with Zarr v2 or
  v3 object naming depending on `:zarr_format` in the backend config/state.

  ## Configuration

  Shared Key convenience options:

  - `:account_name` - Azure storage account name (required unless `:azure_client` given)
  - `:account_key` - Azure storage account key (required unless `:azure_client` given)
  - `:container` - Blob container name (required)
  - `:prefix` - Blob prefix within the container (optional, default `""`)
  - `:zarr_format` - `2` or `3` (optional, default `2`)

  Advanced path — inject a prebuilt client (Shared Key, SAS, Entra, Azurite, etc.):

      azure_client: %AzureSDK.Storage.Client{}

  ## Dependencies

      {:azure_sdk, "~> 0.4.1", optional: true}

  ## Blob structure

  Zarr v2:

      container/prefix/.zarray
      container/prefix/0.0

  Zarr v3:

      container/prefix/zarr.json
      container/prefix/c/0/0
  """

  @behaviour ExZarr.Storage.Backend

  alias ExZarr.Storage.ObjectKeys

  @impl true
  def backend_id, do: :azure_blob

  @impl true
  def init(config) do
    with {:ok, container} <- fetch_required(config, :container),
         {:ok, zarr_format} <- fetch_zarr_format(config),
         {:ok, client} <- build_or_fetch_client(config) do
      {:ok,
       %{
         client: client,
         container: container,
         prefix: Keyword.get(config, :prefix, ""),
         zarr_format: zarr_format,
         account_name: Keyword.get(config, :account_name),
         account_key: Keyword.get(config, :account_key)
       }}
    end
  end

  @impl true
  def open(config), do: init(config)

  @impl true
  def read_chunk(state, chunk_index) do
    blob_name = ObjectKeys.chunk_key(state.prefix, chunk_index, state.zarr_format)

    case blob_api().download(state.client, state.container, blob_name) do
      {:ok, %{content: content}} when is_binary(content) ->
        {:ok, content}

      {:error, error} ->
        normalize_error(error)
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    blob_name = ObjectKeys.chunk_key(state.prefix, chunk_index, state.zarr_format)

    case blob_api().upload(state.client, state.container, blob_name, data) do
      {:ok, _} -> :ok
      {:error, error} -> normalize_error(error)
    end
  end

  @impl true
  def read_metadata(state) do
    blob_name = ObjectKeys.metadata_key(state.prefix, state.zarr_format)

    case blob_api().download(state.client, state.container, blob_name) do
      {:ok, %{content: content}} when is_binary(content) ->
        {:ok, content}

      {:error, error} ->
        # Prefer v3 then v2 when opening without an explicit format
        if state.zarr_format == 2 do
          normalize_error(error)
        else
          fallback = ObjectKeys.metadata_key(state.prefix, 2)

          case blob_api().download(state.client, state.container, fallback) do
            {:ok, %{content: content}} when is_binary(content) -> {:ok, content}
            {:error, _} -> normalize_error(error)
          end
        end
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    version =
      case Jason.decode(metadata) do
        {:ok, %{"zarr_format" => 3}} -> 3
        {:ok, %{zarr_format: 3}} -> 3
        _ -> state.zarr_format
      end

    blob_name = ObjectKeys.metadata_key(state.prefix, version)

    case blob_api().upload(state.client, state.container, blob_name, metadata) do
      {:ok, _} -> :ok
      {:error, error} -> normalize_error(error)
    end
  end

  @impl true
  def list_chunks(state) do
    prefix = ObjectKeys.list_prefix(state.prefix)

    case container_api().list_blobs(state.client, state.container, prefix: prefix) do
      {:ok, blobs} ->
        chunks =
          blobs
          |> Enum.map(&blob_name/1)
          |> Enum.filter(&ObjectKeys.chunk_key?(&1, state.zarr_format))
          |> Enum.map(&ObjectKeys.parse_chunk_key(&1, state.prefix, state.zarr_format))
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, error} ->
        normalize_error(error)
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    blob_name = ObjectKeys.chunk_key(state.prefix, chunk_index, state.zarr_format)

    case blob_api().delete(state.client, state.container, blob_name) do
      {:ok, _} ->
        :ok

      {:error, error} ->
        case normalize_error(error) do
          {:error, :not_found} -> :ok
          other -> other
        end
    end
  end

  @impl true
  def exists?(config) do
    case init(config) do
      {:ok, state} ->
        case container_api().exists?(state.client, state.container) do
          true -> true
          false -> false
          {:error, _} -> false
        end

      {:error, _} ->
        false
    end
  end

  @doc false
  @impl true
  @spec chunk_info(map(), tuple()) :: {:ok, map()} | {:error, term()}
  def chunk_info(state, chunk_index) do
    blob_name = ObjectKeys.chunk_key(state.prefix, chunk_index, state.zarr_format)

    case blob_api().properties(state.client, state.container, blob_name) do
      {:ok, props} ->
        {:ok, %{size: Map.get(props, :content_length, 0), etag: Map.get(props, :etag)}}

      {:error, error} ->
        normalize_error(error)
    end
  end

  @doc false
  @impl true
  @spec read_chunk_range(map(), tuple(), non_neg_integer(), non_neg_integer()) ::
          {:ok, binary()} | {:error, term()}
  def read_chunk_range(state, chunk_index, offset, length)
      when is_integer(offset) and offset >= 0 and is_integer(length) and length >= 0 do
    blob_name = ObjectKeys.chunk_key(state.prefix, chunk_index, state.zarr_format)

    opts =
      if length == 0 do
        []
      else
        [range: {offset, offset + length - 1}]
      end

    opts =
      case Keyword.get_values(opts, :range) do
        [] ->
          opts

        _ ->
          case chunk_info(state, chunk_index) do
            {:ok, %{etag: etag}} when is_binary(etag) -> Keyword.put(opts, :if_match, etag)
            _ -> opts
          end
      end

    if length == 0 do
      {:ok, ""}
    else
      case blob_api().download(state.client, state.container, blob_name, opts) do
        {:ok, %{content: content}} when is_binary(content) -> {:ok, content}
        {:error, error} -> normalize_error(error)
      end
    end
  end

  @doc false
  @impl true
  def capabilities(_state), do: MapSet.new([:range_read])

  ## Private

  defp build_or_fetch_client(config) do
    case Keyword.fetch(config, :azure_client) do
      {:ok, client} when not is_nil(client) ->
        {:ok, client}

      _ ->
        with {:ok, account_name} <- fetch_required(config, :account_name),
             {:ok, account_key} <- fetch_required(config, :account_key),
             :ok <- ensure_azure_sdk() do
          credential = identity_api().new(account_name, account_key)

          client_opts =
            [account: account_name, credential: credential]
            |> maybe_put(:endpoint, Keyword.get(config, :endpoint))

          {:ok, storage_client_api().new(client_opts)}
        end
    end
  end

  defp ensure_azure_sdk do
    if Code.ensure_loaded?(AzureSDK.Storage.Client) do
      :ok
    else
      {:error,
       {:missing_dependency,
        "Azure Blob backend requires {:azure_sdk, \"~> 0.4.1\"} as an optional dependency"}}
    end
  end

  defp maybe_put(opts, _key, nil), do: opts
  defp maybe_put(opts, key, value), do: Keyword.put(opts, key, value)

  defp fetch_zarr_format(config) do
    case Keyword.get(config, :zarr_format, 2) do
      version when version in [2, 3] -> {:ok, version}
      other -> {:error, {:invalid_zarr_format, other}}
    end
  end

  defp fetch_required(config, key) do
    case Keyword.fetch(config, key) do
      {:ok, value} when is_binary(value) and value != "" ->
        {:ok, value}

      {:ok, nil} ->
        {:error, :"#{key}_required"}

      {:ok, _} ->
        {:error, :"invalid_#{key}"}

      :error ->
        {:error, :"#{key}_required"}
    end
  end

  defp blob_name(%{name: name}) when is_binary(name), do: name
  defp blob_name(%{"name" => name}) when is_binary(name), do: name
  defp blob_name(name) when is_binary(name), do: name
  defp blob_name(_), do: ""

  defp normalize_error(%{status: 404}), do: {:error, :not_found}
  defp normalize_error(%{status_code: 404}), do: {:error, :not_found}

  defp normalize_error(error) when is_map(error) do
    status = Map.get(error, :status) || Map.get(error, :status_code)

    if status == 404 do
      {:error, :not_found}
    else
      {:error, {:azure_error, error}}
    end
  end

  defp normalize_error(error), do: {:error, {:azure_error, error}}

  defp blob_api do
    Application.get_env(:ex_zarr, :azure_blob_module, AzureSDK.Storage.Blob)
  end

  defp container_api do
    Application.get_env(:ex_zarr, :azure_container_module, AzureSDK.Storage.Container)
  end

  defp identity_api do
    Application.get_env(
      :ex_zarr,
      :azure_identity_module,
      AzureSDK.Identity.SharedKeyCredential
    )
  end

  defp storage_client_api do
    Application.get_env(:ex_zarr, :azure_storage_client_module, AzureSDK.Storage.Client)
  end
end
