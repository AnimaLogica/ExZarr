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
  - `:zarr_format` (or `:zarr_version`) - `2` or `3` (optional, default `2`;
    updated from the array metadata on create/open, and opening probes both
    `zarr.json` and `.zarray`)

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
         {:ok, layout} <- ObjectKeys.config_layout(config),
         {:ok, client} <- build_or_fetch_client(config) do
      # Credentials live only inside the client, never in backend state.
      {:ok,
       Map.merge(layout, %{
         client: client,
         container: container,
         prefix: Keyword.get(config, :prefix, "")
       })}
    end
  end

  @impl true
  def open(config), do: init(config)

  @doc false
  @impl true
  def put_layout(state, layout),
    do: Map.merge(state, Map.take(layout, [:zarr_format, :chunk_key_encoding]))

  @impl true
  def read_chunk(state, chunk_index) do
    blob_name = ObjectKeys.state_chunk_key(state, chunk_index)

    case blob_api().download(state.client, state.container, blob_name) do
      {:ok, %{content: content}} when is_binary(content) ->
        {:ok, content}

      {:error, error} ->
        normalize_error(error)
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    blob_name = ObjectKeys.state_chunk_key(state, chunk_index)

    case blob_api().upload(state.client, state.container, blob_name, data) do
      {:ok, _} -> :ok
      {:error, error} -> normalize_error(error)
    end
  end

  @impl true
  def read_metadata(state) do
    state.prefix
    |> ObjectKeys.metadata_keys(state.zarr_format)
    |> Enum.reduce_while({:error, :not_found}, fn blob_name, _acc ->
      case blob_api().download(state.client, state.container, blob_name) do
        {:ok, %{content: content}} when is_binary(content) ->
          {:halt, {:ok, content}}

        {:error, error} ->
          case normalize_error(error) do
            {:error, :not_found} -> {:cont, {:error, :not_found}}
            other -> {:halt, other}
          end
      end
    end)
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    version = ObjectKeys.metadata_version(metadata, state.zarr_format)
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
          |> Enum.map(
            &ObjectKeys.parse_chunk_key(
              blob_name(&1),
              state.prefix,
              state.zarr_format,
              Map.get(state, :chunk_key_encoding)
            )
          )
          |> Enum.reject(&is_nil/1)

        {:ok, chunks}

      {:error, error} ->
        normalize_error(error)
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    blob_name = ObjectKeys.state_chunk_key(state, chunk_index)

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
  def chunk_info(state, chunk_index) do
    blob_name = ObjectKeys.state_chunk_key(state, chunk_index)

    case blob_api().properties(state.client, state.container, blob_name) do
      {:ok, %{content_length: size} = props} when is_integer(size) ->
        {:ok, %{size: size, etag: Map.get(props, :etag)}}

      {:ok, _props} ->
        {:error, {:azure_error, :missing_content_length}}

      {:error, error} ->
        normalize_error(error)
    end
  end

  @doc false
  @impl true
  def read_chunk_range(state, chunk_index, offset, length),
    do: read_chunk_range(state, chunk_index, offset, length, [])

  @doc false
  @impl true
  def read_chunk_range(state, chunk_index, offset, length, opts)
      when is_integer(offset) and offset >= 0 and is_integer(length) and length > 0 do
    blob_name = ObjectKeys.state_chunk_key(state, chunk_index)

    download_opts =
      [range: {offset, offset + length - 1}]
      |> maybe_put(:if_match, Keyword.get(opts, :if_match))

    case blob_api().download(state.client, state.container, blob_name, download_opts) do
      {:ok, %{content: content}} when is_binary(content) -> {:ok, content}
      {:error, error} -> normalize_error(error)
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

  defp normalize_error(error) when is_map(error) do
    case Map.get(error, :status) || Map.get(error, :status_code) do
      404 -> {:error, :not_found}
      412 -> {:error, :precondition_failed}
      _ -> {:error, {:azure_error, error}}
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
