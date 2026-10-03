defmodule ExZarr.Storage.ObjectKeys do
  @moduledoc """
  Central Zarr object-key construction for storage backends.

  Cloud and filesystem backends should store/fetch the keys produced here
  rather than inventing Zarr naming conventions independently.

  Chunk keys follow the array's chunk key encoding:

    * Zarr v2: indices joined by `"."` (`"0.1"`)
    * Zarr v3 `default` encoding: `"c"` + separator + indices (`"c/0/1"`,
      or `"c.0.1"` with separator `"."`; a 0-D chunk is `"c"`)
    * Zarr v3 `v2` encoding: indices joined by the separator (default `"."`;
      a 0-D chunk is `"0"`)
  """

  alias ExZarr.Version

  @type version :: 2 | 3
  @type prefix :: String.t()
  @type chunk_index :: tuple()
  @type encoding :: %{name: String.t(), separator: String.t()}

  @doc """
  Builds a metadata object key for the given Zarr version and optional prefix.
  """
  @spec metadata_key(prefix(), version(), :array | :group) :: String.t()
  def metadata_key(prefix \\ "", version \\ 2, node_type \\ :array)

  def metadata_key("", version, node_type), do: Version.metadata_filename(version, node_type)

  def metadata_key(prefix, version, node_type) when is_binary(prefix) do
    join(prefix, Version.metadata_filename(version, node_type))
  end

  @doc """
  Reads the object layout from backend config.

  Accepts `:zarr_format` or `:zarr_version` (default `2`) and an optional v3
  `:chunk_key_encoding` map.
  """
  @spec config_layout(keyword()) ::
          {:ok, %{zarr_format: version(), chunk_key_encoding: map() | nil}} | {:error, term()}
  def config_layout(config) do
    case Keyword.get(config, :zarr_format) || Keyword.get(config, :zarr_version) || 2 do
      version when version in [2, 3] ->
        {:ok,
         %{zarr_format: version, chunk_key_encoding: Keyword.get(config, :chunk_key_encoding)}}

      other ->
        {:error, {:invalid_zarr_format, other}}
    end
  end

  @doc """
  Builds the chunk key for a backend state map holding `:prefix`,
  `:zarr_format` and optionally `:chunk_key_encoding`.
  """
  @spec state_chunk_key(
          %{
            required(:prefix) => prefix(),
            required(:zarr_format) => version(),
            optional(atom()) => term()
          },
          chunk_index()
        ) :: String.t()
  def state_chunk_key(%{prefix: prefix, zarr_format: version} = state, chunk_index) do
    chunk_key(prefix, chunk_index, version, Map.get(state, :chunk_key_encoding))
  end

  @doc """
  Metadata keys to probe when opening, preferred version first.
  """
  @spec metadata_keys(prefix(), version()) :: [String.t()]
  def metadata_keys(prefix, preferred) do
    other = if preferred == 3, do: 2, else: 3
    [metadata_key(prefix, preferred), metadata_key(prefix, other)]
  end

  @doc """
  Returns the Zarr version declared by a metadata JSON document, or `default`.
  """
  @spec metadata_version(binary(), version()) :: version()
  def metadata_version(metadata_json, default) when is_binary(metadata_json) do
    case Jason.decode(metadata_json) do
      {:ok, %{"zarr_format" => version}} when version in [2, 3] -> version
      _ -> default
    end
  end

  @doc """
  Normalizes a chunk key encoding for `version`.

  Accepts `nil` (the version default) or a v3 `chunk_key_encoding` map with
  string or atom keys.
  """
  @spec encoding(version(), map() | nil) :: encoding()
  def encoding(2, _), do: %{name: "v2", separator: "."}
  def encoding(3, nil), do: %{name: "default", separator: "/"}

  def encoding(3, %{} = cke) do
    name = Map.get(cke, "name") || Map.get(cke, :name) || "default"
    config = Map.get(cke, "configuration") || Map.get(cke, :configuration) || %{}
    default_sep = if name == "v2", do: ".", else: "/"
    sep = Map.get(config, "separator") || Map.get(config, :separator) || default_sep
    %{name: name, separator: sep}
  end

  @doc """
  Builds a chunk object key for the given Zarr version and optional prefix.

  `chunk_key_encoding` is the v3 metadata field (ignored for v2).
  """
  @spec chunk_key(prefix(), chunk_index(), version(), map() | nil) :: String.t()
  def chunk_key(prefix \\ "", chunk_index, version \\ 2, chunk_key_encoding \\ nil)

  def chunk_key(prefix, chunk_index, version, chunk_key_encoding) when is_binary(prefix) do
    name = encode(chunk_index, encoding(version, chunk_key_encoding))
    if prefix == "", do: name, else: join(prefix, name)
  end

  @doc """
  Returns the listing prefix (with trailing slash when non-empty).
  """
  @spec list_prefix(prefix()) :: String.t()
  def list_prefix(""), do: ""
  def list_prefix(prefix) when is_binary(prefix), do: String.trim_trailing(prefix, "/") <> "/"

  @doc """
  Parses a chunk object key into a chunk index tuple.

  Returns `nil` for keys outside `prefix`, keys belonging to nested nodes, and
  non-chunk objects such as metadata.
  """
  @spec parse_chunk_key(String.t(), prefix(), version(), map() | nil) :: chunk_index() | nil
  def parse_chunk_key(name, prefix, version, chunk_key_encoding \\ nil) when is_binary(name) do
    case strip_prefix(name, prefix) do
      {:ok, relative} -> decode(relative, encoding(version, chunk_key_encoding))
      :error -> nil
    end
  end

  defp encode(chunk_index, %{name: "default", separator: sep}) do
    case Tuple.to_list(chunk_index) do
      [] -> "c"
      indices -> "c" <> sep <> Enum.map_join(indices, sep, &Integer.to_string/1)
    end
  end

  defp encode(chunk_index, %{separator: sep}) do
    case Tuple.to_list(chunk_index) do
      [] -> "0"
      indices -> Enum.map_join(indices, sep, &Integer.to_string/1)
    end
  end

  defp decode("c", %{name: "default"}), do: {}

  defp decode(relative, %{name: "default", separator: sep}) do
    case String.split(relative, sep) do
      ["c" | [_ | _] = parts] -> parse_indices(parts)
      _ -> nil
    end
  end

  defp decode(relative, %{separator: sep}) do
    # With a "." separator a "/" means the object belongs to a nested node.
    if sep != "/" and String.contains?(relative, "/") do
      nil
    else
      relative |> String.split(sep) |> parse_indices()
    end
  end

  defp parse_indices(parts) do
    if Enum.all?(parts, &String.match?(&1, ~r/^\d+$/)) do
      parts |> Enum.map(&String.to_integer/1) |> List.to_tuple()
    end
  end

  defp strip_prefix(name, ""), do: {:ok, name}

  defp strip_prefix(name, prefix) do
    head = list_prefix(prefix)

    if String.starts_with?(name, head) and byte_size(name) > byte_size(head) do
      {:ok, binary_part(name, byte_size(head), byte_size(name) - byte_size(head))}
    else
      :error
    end
  end

  defp join(prefix, name) do
    String.trim_trailing(prefix, "/") <> "/" <> name
  end
end
