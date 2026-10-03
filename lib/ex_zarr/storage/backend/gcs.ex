defmodule ExZarr.Storage.Backend.GCS do
  @moduledoc """
  Google Cloud Storage (GCS) backend for Zarr arrays.

  Stores chunks and metadata in Google Cloud Storage, providing globally
  distributed object storage with strong consistency.

  ## Configuration

  Requires the following options:
  - `:bucket` - GCS bucket name (required)
  - `:prefix` - Object prefix/path within bucket (optional, default: "")
  - `:credentials` - Path to service account JSON file or credentials map (required)
  - `:endpoint_url` - Custom endpoint URL for fake-gcs-server or compatible services (optional)

  For testing with fake-gcs-server, set the `GCS_ENDPOINT_URL` environment variable:
  ```bash
  export GCS_ENDPOINT_URL=http://localhost:4443  # fake-gcs-server
  ```

  ## Dependencies

  Requires the `goth` and `req` packages:

  ```elixir
  {:goth, "~> 1.4"},
  {:req, "~> 0.6.1"}
  ```

  ## Authentication

  Uses Google Cloud service account credentials. Credentials can be provided:
  - As a path to a JSON key file: `credentials: "/path/to/service-account.json"`
  - As a decoded map: `credentials: %{...}`
  - Via GOOGLE_APPLICATION_CREDENTIALS environment variable

  ## Example

  ```elixir
  # Register the GCS backend
  :ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.GCS)

  # Create array with GCS storage
  {:ok, array} = ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    dtype: :float64,
    storage: :gcs,
    bucket: "my-zarr-bucket",
    prefix: "experiments/array1",
    credentials: System.get_env("GOOGLE_APPLICATION_CREDENTIALS")
  )

  # Write and read data
  ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})
  {:ok, result} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {100, 100})
  ```

  ## GCS Structure

  Object names follow `ExZarr.Storage.ObjectKeys`. Zarr v2 arrays:
  ```
  gs://bucket/prefix/.zarray           # Metadata
  gs://bucket/prefix/0.0               # Chunk at index (0, 0)
  ```

  Zarr v3 arrays (default chunk key encoding):
  ```
  gs://bucket/prefix/zarr.json         # Metadata
  gs://bucket/prefix/c/0/0             # Chunk at index (0, 0)
  ```

  The version is taken from `:zarr_format` / `:zarr_version` in the config and
  updated from the array metadata on create/open. Opening probes both
  `zarr.json` and `.zarray`.

  ## Performance Considerations

  - Objects are read/written individually
  - Use appropriate chunk sizes for your access patterns
  - Consider using Cloud CDN for read-heavy workloads
  - Configure appropriate storage classes (Standard/Nearline/Coldline/Archive)

  ## Error Handling

  GCS errors are returned as `{:error, reason}` tuples.
  Common errors:
  - `:bucket_not_found` - Bucket doesn't exist
  - `:access_denied` - Insufficient permissions
  - `:network_error` - Network connectivity issues
  """

  @behaviour ExZarr.Storage.Backend

  alias ExZarr.Storage.ObjectKeys

  @base_url "https://storage.googleapis.com/storage/v1"
  @upload_url "https://storage.googleapis.com/upload/storage/v1"

  @impl true
  def backend_id, do: :gcs

  @impl true
  def init(config) do
    with {:ok, bucket} <- fetch_required(config, :bucket),
         {:ok, layout} <- ObjectKeys.config_layout(config),
         {:ok, goth_name} <- setup_goth(config) do
      prefix = Keyword.get(config, :prefix, "")
      endpoint_url = Keyword.get(config, :endpoint_url) || System.get_env("GCS_ENDPOINT_URL")

      {base_url, upload_url} = build_urls(endpoint_url)

      state =
        Map.merge(layout, %{
          bucket: bucket,
          prefix: prefix,
          goth_name: goth_name,
          base_url: base_url,
          upload_url: upload_url
        })

      {:ok, state}
    end
  end

  @impl true
  def open(config) do
    # Same as init for GCS
    init(config)
  end

  @doc false
  @impl true
  def put_layout(state, layout),
    do: Map.merge(state, Map.take(layout, [:zarr_format, :chunk_key_encoding]))

  @impl true
  def read_chunk(state, chunk_index) do
    object_name = ObjectKeys.state_chunk_key(state, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url =
        "#{state.base_url}/b/#{state.bucket}/o/#{encode_name(object_name)}"

      case req().get(url,
             params: [alt: "media"],
             headers: [{"authorization", "Bearer #{token}"}],
             decode_body: false
           ) do
        {:ok, %{status: 200, body: body}} when is_binary(body) ->
          {:ok, body}

        {:ok, %{status: 200, body: body}} ->
          {:ok, IO.iodata_to_binary([body])}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    object_name = ObjectKeys.state_chunk_key(state, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.upload_url}/b/#{state.bucket}/o"

      case req().post(url,
             params: [uploadType: "media", name: object_name],
             headers: [
               {"authorization", "Bearer #{token}"},
               {"content-type", "application/octet-stream"}
             ],
             body: data
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def read_metadata(state) do
    with {:ok, token} <- get_access_token(state.goth_name) do
      state.prefix
      |> ObjectKeys.metadata_keys(state.zarr_format)
      |> Enum.reduce_while({:error, :not_found}, fn object_name, _acc ->
        case fetch_metadata_object(state, token, object_name) do
          {:error, :not_found} -> {:cont, {:error, :not_found}}
          result -> {:halt, result}
        end
      end)
    end
  end

  defp fetch_metadata_object(state, token, object_name) do
    url = "#{state.base_url}/b/#{state.bucket}/o/#{encode_name(object_name)}"

    case req().get(url,
           params: [alt: "media"],
           headers: [{"authorization", "Bearer #{token}"}],
           decode_body: false
         ) do
      {:ok, %{status: 200, body: body}} when is_binary(body) ->
        {:ok, body}

      {:ok, %{status: 200, body: body}} when is_map(body) ->
        {:ok, Jason.encode!(body)}

      {:ok, %{status: 404}} ->
        {:error, :not_found}

      {:ok, response} ->
        {:error, {:gcs_error, response.status}}

      {:error, reason} ->
        {:error, {:gcs_error, reason}}
    end
  end

  @impl true
  def write_metadata(state, metadata, _opts) when is_binary(metadata) do
    version = ObjectKeys.metadata_version(metadata, state.zarr_format)
    object_name = ObjectKeys.metadata_key(state.prefix, version)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.upload_url}/b/#{state.bucket}/o"

      case req().post(url,
             params: [uploadType: "media", name: object_name],
             headers: [
               {"authorization", "Bearer #{token}"},
               {"content-type", "application/json"}
             ],
             body: metadata
           ) do
        {:ok, %{status: status}} when status in 200..299 ->
          :ok

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def list_chunks(state) do
    prefix = ObjectKeys.list_prefix(state.prefix)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.base_url}/b/#{state.bucket}/o"

      case req().get(url,
             params: [prefix: prefix],
             headers: [{"authorization", "Bearer #{token}"}]
           ) do
        {:ok, %{status: 200, body: %{"items" => items}}} when is_list(items) ->
          chunks =
            items
            |> Enum.map(
              &ObjectKeys.parse_chunk_key(
                &1["name"],
                state.prefix,
                state.zarr_format,
                Map.get(state, :chunk_key_encoding)
              )
            )
            |> Enum.reject(&is_nil/1)

          {:ok, chunks}

        {:ok, %{status: 200, body: _}} ->
          {:ok, []}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def delete_chunk(state, chunk_index) do
    object_name = ObjectKeys.state_chunk_key(state, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url =
        "#{state.base_url}/b/#{state.bucket}/o/#{encode_name(object_name)}"

      case req().delete(url, headers: [{"authorization", "Bearer #{token}"}]) do
        {:ok, %{status: status}} when status in 200..299 or status == 404 ->
          :ok

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @impl true
  def exists?(config) do
    with {:ok, bucket} <- fetch_required(config, :bucket),
         {:ok, goth_name} <- setup_goth(config),
         {:ok, token} <- get_access_token(goth_name) do
      endpoint_url = Keyword.get(config, :endpoint_url) || System.get_env("GCS_ENDPOINT_URL")
      {base_url, _upload_url} = build_urls(endpoint_url)
      url = "#{base_url}/b/#{bucket}"

      case req().get(url, headers: [{"authorization", "Bearer #{token}"}]) do
        {:ok, %{status: 200}} -> true
        _ -> false
      end
    else
      _ -> false
    end
  end

  @doc false
  @impl true
  def chunk_info(state, chunk_index) do
    object_name = ObjectKeys.state_chunk_key(state, chunk_index)

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.base_url}/b/#{state.bucket}/o/#{encode_name(object_name)}"

      case req().get(url, headers: [{"authorization", "Bearer #{token}"}]) do
        {:ok, %{status: 200, body: %{} = body}} ->
          case parse_size(body["size"]) do
            # The object generation is the version token used for ifGenerationMatch.
            size when is_integer(size) -> {:ok, %{size: size, etag: body["generation"]}}
            nil -> {:error, {:gcs_error, :missing_size}}
          end

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
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
    object_name = ObjectKeys.state_chunk_key(state, chunk_index)

    params =
      case Keyword.get(opts, :if_match) do
        nil -> [alt: "media"]
        generation -> [alt: "media", ifGenerationMatch: generation]
      end

    with {:ok, token} <- get_access_token(state.goth_name) do
      url = "#{state.base_url}/b/#{state.bucket}/o/#{encode_name(object_name)}"

      case req().get(url,
             params: params,
             headers: [
               {"authorization", "Bearer #{token}"},
               {"range", "bytes=#{offset}-#{offset + length - 1}"}
             ],
             decode_body: false
           ) do
        {:ok, %{status: status, body: body}} when status in [200, 206] and is_binary(body) ->
          {:ok, body}

        {:ok, %{status: 404}} ->
          {:error, :not_found}

        {:ok, %{status: 412}} ->
          {:error, :precondition_failed}

        {:ok, response} ->
          {:error, {:gcs_error, response.status}}

        {:error, reason} ->
          {:error, {:gcs_error, reason}}
      end
    end
  end

  @doc false
  @impl true
  def capabilities(_state), do: MapSet.new([:range_read])

  ## Private Helpers

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

  defp setup_goth(config) do
    credentials = Keyword.get(config, :credentials)

    cond do
      is_binary(credentials) and File.exists?(credentials) ->
        # Credentials file path
        name = :"goth_#{:erlang.unique_integer([:positive])}"

        case goth().start_link(
               name: name,
               source: {:service_account, credentials}
             ) do
          {:ok, _pid} -> {:ok, name}
          {:error, reason} -> {:error, {:goth_error, reason}}
        end

      is_map(credentials) ->
        # Credentials map
        name = :"goth_#{:erlang.unique_integer([:positive])}"

        case goth().start_link(
               name: name,
               source: {:service_account, credentials}
             ) do
          {:ok, _pid} -> {:ok, name}
          {:error, reason} -> {:error, {:goth_error, reason}}
        end

      is_nil(credentials) ->
        # Try default credentials
        name = :"goth_#{:erlang.unique_integer([:positive])}"

        case goth().start_link(name: name) do
          {:ok, _pid} -> {:ok, name}
          {:error, reason} -> {:error, {:goth_error, reason}}
        end

      true ->
        {:error, :invalid_credentials}
    end
  end

  defp get_access_token(goth_name) do
    case goth().fetch(goth_name) do
      {:ok, %{token: token}} -> {:ok, token}
      {:error, reason} -> {:error, {:goth_error, reason}}
    end
  end

  defp encode_name(object_name), do: URI.encode(object_name, &URI.char_unreserved?/1)

  defp parse_size(size) when is_integer(size), do: size

  defp parse_size(size) when is_binary(size) do
    case Integer.parse(size) do
      {int, ""} -> int
      _ -> nil
    end
  end

  defp parse_size(_), do: nil

  defp build_urls(nil) do
    {@base_url, @upload_url}
  end

  defp build_urls(endpoint_url) when is_binary(endpoint_url) do
    base_url = "#{endpoint_url}/storage/v1"
    upload_url = "#{endpoint_url}/upload/storage/v1"
    {base_url, upload_url}
  end

  # Allow injection for testing
  defp req do
    Application.get_env(:ex_zarr, :req_module, Req)
  end

  defp goth do
    Application.get_env(:ex_zarr, :goth_module, Goth)
  end
end
