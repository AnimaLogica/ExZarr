defmodule ExZarr.Storage.ObjectKeys do
  @moduledoc """
  Central Zarr object-key construction for storage backends.

  Cloud and filesystem backends should store/fetch the keys produced here
  rather than inventing Zarr naming conventions independently.
  """

  alias ExZarr.{ChunkKey, Version}

  @type version :: 2 | 3
  @type prefix :: String.t()
  @type chunk_index :: tuple()

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
  Builds a chunk object key for the given Zarr version and optional prefix.
  """
  @spec chunk_key(prefix(), chunk_index(), version()) :: String.t()
  def chunk_key(prefix \\ "", chunk_index, version \\ 2)

  def chunk_key("", chunk_index, version) do
    ChunkKey.encode(chunk_index, version)
  end

  def chunk_key(prefix, chunk_index, version) when is_binary(prefix) do
    join(prefix, ChunkKey.encode(chunk_index, version))
  end

  @doc """
  Returns the listing prefix (with trailing slash when non-empty).
  """
  @spec list_prefix(prefix()) :: String.t()
  def list_prefix(""), do: ""
  def list_prefix(prefix) when is_binary(prefix), do: String.trim_trailing(prefix, "/") <> "/"

  @doc """
  Returns true if the object basename looks like a chunk key for the version.
  """
  @spec chunk_key?(String.t(), version()) :: boolean()
  def chunk_key?(name, version) when is_binary(name) do
    relative = Path.basename(name)

    case version do
      2 -> String.match?(relative, ~r/^\d+(\.\d+)*$/)
      3 -> String.match?(name, ~r{(^|/)c/\d}) or String.match?(relative, ~r/^\d+$/)
    end
  end

  @doc """
  Parses a chunk object key into a chunk index tuple.
  """
  @spec parse_chunk_key(String.t(), prefix(), version()) :: chunk_index() | nil
  def parse_chunk_key(name, prefix, version) do
    relative =
      name
      |> trim_prefix(prefix)
      |> String.trim_leading("/")

    case ChunkKey.decode(relative, version) do
      {:ok, index} -> index
      {:error, _} -> nil
    end
  rescue
    _ -> nil
  end

  defp join(prefix, name) do
    String.trim_trailing(prefix, "/") <> "/" <> name
  end

  defp trim_prefix(name, ""), do: name

  defp trim_prefix(name, prefix) do
    trimmed = String.trim_trailing(prefix, "/")

    cond do
      String.starts_with?(name, trimmed <> "/") ->
        String.trim_leading(name, trimmed <> "/")

      String.starts_with?(name, trimmed) ->
        String.trim_leading(name, trimmed)

      true ->
        name
    end
  end
end
