defmodule ExZarr.Codecs.ShardingIndexed do
  @moduledoc """
  Zarr `sharding_indexed` codec (accepted specification v1.0).

  The shard index is a dense C-order array of shape `chunks_per_shard ++ [2]`
  holding little-endian `uint64` `(offset, nbytes)` pairs. Empty inner chunks
  use the sentinel `2^64 - 1` for both values.

  Offsets are relative to the start of the entire shard object. Index size is
  computed from the number of inner chunks and the fixed-size index codec
  pipeline (no private trailing index-size field).

  See: https://zarr-specs.readthedocs.io/en/latest/v3/codecs/sharding-indexed/v1.0.html
  """

  alias ExZarr.Codecs.PipelineV3

  @empty_sentinel 0xFFFFFFFFFFFFFFFF

  @type chunk_index :: tuple()
  @type chunk_data :: binary()
  @type chunks_map :: %{chunk_index() => chunk_data()}
  @type shard_binary :: binary()
  @type index_location :: :start | :end

  @type t :: %__MODULE__{
          chunk_shape: tuple(),
          codecs: [map()],
          index_codecs: [map()],
          index_location: index_location()
        }

  defstruct [:chunk_shape, :codecs, :index_codecs, :index_location]

  @doc """
  Initializes the sharding codec from configuration.
  """
  @spec init(map()) :: {:ok, t()} | {:error, term()}
  def init(config) when is_map(config) do
    with {:ok, chunk_shape} <- parse_chunk_shape(config),
         {:ok, codecs} <- parse_codecs(config),
         {:ok, index_codecs} <- parse_index_codecs(config),
         :ok <- validate_index_codecs(index_codecs),
         {:ok, index_location} <- parse_index_location(config) do
      {:ok,
       %__MODULE__{
         chunk_shape: chunk_shape,
         codecs: codecs,
         index_codecs: index_codecs,
         index_location: index_location
       }}
    end
  end

  @doc """
  Encodes a map of **local** chunk indices into a shard binary.
  """
  @spec encode(chunks_map(), t()) :: {:ok, shard_binary()} | {:error, term()}
  def encode(chunks, %__MODULE__{} = codec) when is_map(chunks) do
    with :ok <- validate_local_keys(chunks, codec.chunk_shape),
         {:ok, encoded_chunks} <- encode_individual_chunks(chunks, codec.codecs),
         {:ok, data_blob, index_entries} <- pack_chunks(encoded_chunks, codec),
         {:ok, encoded_index} <- encode_index(index_entries, codec) do
      embed_index(data_blob, encoded_index, codec.index_location)
    end
  end

  @doc """
  Decodes one **local** chunk from a shard binary.
  """
  @spec decode_chunk(shard_binary(), chunk_index(), t()) ::
          {:ok, chunk_data()} | {:error, term()}
  def decode_chunk(shard_binary, chunk_index, %__MODULE__{} = codec)
      when is_binary(shard_binary) and is_tuple(chunk_index) do
    with :ok <- validate_local_key(chunk_index, codec.chunk_shape),
         {:ok, index_entries, data_region} <- extract_index_and_data(shard_binary, codec),
         {:ok, {offset, nbytes}} <- lookup_entry(index_entries, chunk_index, codec.chunk_shape) do
      cond do
        empty_entry?(offset, nbytes) ->
          {:error, {:chunk_not_found, chunk_index}}

        offset + nbytes > byte_size(shard_binary) ->
          {:error, {:invalid_shard_index, :offset_out_of_bounds}}

        true ->
          # Offsets are relative to the full shard object
          <<_::binary-size(offset), chunk::binary-size(nbytes), _::binary>> = shard_binary
          _ = data_region
          decode_individual_chunk(chunk, codec.codecs)
      end
    end
  end

  @doc """
  Decodes all present (non-sentinel) **local** chunks from a shard.
  """
  @spec decode(shard_binary(), t()) :: {:ok, chunks_map()} | {:error, term()}
  def decode(shard_binary, %__MODULE__{} = codec) when is_binary(shard_binary) do
    with {:ok, index_entries, _data} <- extract_index_and_data(shard_binary, codec) do
      Enum.reduce_while(all_local_indices(codec.chunk_shape), {:ok, %{}}, fn local, {:ok, acc} ->
        case lookup_entry(index_entries, local, codec.chunk_shape) do
          {:ok, {offset, nbytes}} ->
            if empty_entry?(offset, nbytes) do
              {:cont, {:ok, acc}}
            else
              if offset + nbytes > byte_size(shard_binary) do
                {:halt, {:error, {:invalid_shard_index, :offset_out_of_bounds}}}
              else
                <<_::binary-size(offset), chunk::binary-size(nbytes), _::binary>> = shard_binary

                case decode_individual_chunk(chunk, codec.codecs) do
                  {:ok, decoded} -> {:cont, {:ok, Map.put(acc, local, decoded)}}
                  error -> {:halt, error}
                end
              end
            end

          error ->
            {:halt, error}
        end
      end)
    end
  end

  @doc """
  Returns `{offset, length}` of the encoded index within a shard of `shard_size` bytes.
  """
  @spec index_byte_range(t(), non_neg_integer()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def index_byte_range(%__MODULE__{} = codec, shard_size) when is_integer(shard_size) do
    index_len = encoded_index_byte_length(codec)

    cond do
      shard_size < index_len ->
        {:error, {:invalid_shard_index, :too_short}}

      codec.index_location == :end ->
        {:ok, {shard_size - index_len, index_len}}

      true ->
        {:ok, {0, index_len}}
    end
  end

  @doc """
  Decodes an encoded index binary into local-index entries.
  """
  @spec decode_index_bytes(binary(), t()) :: {:ok, map()} | {:error, term()}
  def decode_index_bytes(index_bin, %__MODULE__{} = codec) when is_binary(index_bin) do
    decode_index(index_bin, codec)
  end

  @doc """
  Looks up a local chunk entry in a decoded index map.
  """
  @spec index_entry(map(), chunk_index()) ::
          {:ok, {non_neg_integer() | integer(), non_neg_integer() | integer()}} | {:error, term()}
  def index_entry(entries, local_index) when is_map(entries) do
    lookup_entry(entries, local_index, nil)
  end

  @doc """
  Returns true when an index entry is the empty sentinel.
  """
  @spec empty_entry?({integer(), integer()}) :: boolean()
  def empty_entry?({offset, nbytes}), do: empty_entry?(offset, nbytes)

  @doc """
  Returns the encoded index byte length for this codec (fixed-size pipelines only).
  """
  @spec encoded_index_byte_length(t()) :: non_neg_integer()
  def encoded_index_byte_length(%__MODULE__{} = codec) do
    raw = raw_index_byte_length(codec.chunk_shape)
    expand_fixed_index_size(raw, codec.index_codecs)
  end

  @doc """
  Detects the legacy ExZarr-private sparse index format (pre-1.2.0).

  Call this when a standard decode fails and you need a migration error.
  """
  @spec legacy_format?(binary()) :: boolean()
  def legacy_format?(<<num_chunks::little-unsigned-32, rest::binary>>)
      when num_chunks > 0 and num_chunks < 1_000_000 do
    byte_size(rest) >= num_chunks * 8
  end

  def legacy_format?(_), do: false

  @doc false
  def empty_sentinel, do: @empty_sentinel

  @doc """
  Decodes an already-extracted inner-chunk payload through the inner codec pipeline.
  """
  @spec decode_chunk_payload(binary(), t()) :: {:ok, chunk_data()} | {:error, term()}
  def decode_chunk_payload(payload, %__MODULE__{} = codec) when is_binary(payload) do
    decode_individual_chunk(payload, codec.codecs)
  end

  ## Private

  defp parse_chunk_shape(%{"chunk_shape" => shape}) when is_list(shape),
    do: {:ok, List.to_tuple(shape)}

  defp parse_chunk_shape(%{chunk_shape: shape}) when is_tuple(shape), do: {:ok, shape}

  defp parse_chunk_shape(%{chunk_shape: shape}) when is_list(shape),
    do: {:ok, List.to_tuple(shape)}

  defp parse_chunk_shape(_), do: {:error, :missing_chunk_shape}

  defp parse_codecs(%{"codecs" => codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_codecs(%{codecs: codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_codecs(_), do: {:error, :missing_codecs}

  defp parse_index_codecs(%{"index_codecs" => codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_index_codecs(%{index_codecs: codecs}) when is_list(codecs), do: {:ok, codecs}

  defp parse_index_codecs(_) do
    {:ok,
     [
       %{"name" => "bytes", "configuration" => %{}},
       %{"name" => "crc32c", "configuration" => %{}}
     ]}
  end

  defp parse_index_location(%{"index_location" => "start"}), do: {:ok, :start}
  defp parse_index_location(%{"index_location" => "end"}), do: {:ok, :end}
  defp parse_index_location(%{index_location: :start}), do: {:ok, :start}
  defp parse_index_location(%{index_location: :end}), do: {:ok, :end}
  defp parse_index_location(_), do: {:ok, :end}

  defp validate_index_codecs(codecs) do
    names =
      Enum.map(codecs, fn c -> Map.get(c, "name") || Map.get(c, :name) end)

    cond do
      names == [] ->
        {:error, {:invalid_index_codecs, :empty}}

      Enum.any?(names, &(&1 in ["gzip", "zstd", "blosc", "lz4", "bz2", "zlib"])) ->
        {:error, {:invalid_index_codecs, :variable_size_not_allowed}}

      true ->
        :ok
    end
  end

  defp validate_local_keys(chunks, chunk_shape) do
    Enum.reduce_while(Map.keys(chunks), :ok, fn key, :ok ->
      case validate_local_key(key, chunk_shape) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_local_key(index, chunk_shape)
       when tuple_size(index) == tuple_size(chunk_shape) do
    ok? =
      Enum.zip(Tuple.to_list(index), Tuple.to_list(chunk_shape))
      |> Enum.all?(fn {i, n} -> is_integer(i) and i >= 0 and i < n end)

    if ok?, do: :ok, else: {:error, {:invalid_chunk_index, index}}
  end

  defp validate_local_key(index, _), do: {:error, {:invalid_chunk_index, index}}

  defp encode_individual_chunks(chunks, codecs) do
    Enum.reduce_while(chunks, {:ok, %{}}, fn {chunk_idx, chunk_data}, {:ok, acc} ->
      case apply_codecs(chunk_data, codecs, :encode) do
        {:ok, encoded} -> {:cont, {:ok, Map.put(acc, chunk_idx, encoded)}}
        error -> {:halt, error}
      end
    end)
  end

  defp pack_chunks(encoded_chunks, codec) do
    # Spec: offsets relative to full shard. For index at end, index follows data,
    # so data starts at offset 0. For index at start, data starts after encoded index.
    index_len = encoded_index_byte_length(codec)
    data_start = if codec.index_location == :start, do: index_len, else: 0

    sorted = Enum.sort(encoded_chunks)

    {data, entries, _offset} =
      Enum.reduce(sorted, {<<>>, %{}, data_start}, fn {idx, bin}, {data_acc, entries, offset} ->
        size = byte_size(bin)
        {<<data_acc::binary, bin::binary>>, Map.put(entries, idx, {offset, size}), offset + size}
      end)

    # Fill dense index with sentinels then present entries
    dense =
      for local <- all_local_indices(codec.chunk_shape), into: %{} do
        {local, Map.get(entries, local, {@empty_sentinel, @empty_sentinel})}
      end

    {:ok, data, dense}
  end

  defp encode_index(entries, codec) do
    raw =
      for local <- all_local_indices(codec.chunk_shape), into: <<>> do
        {offset, nbytes} = Map.fetch!(entries, local)
        <<offset::little-unsigned-64, nbytes::little-unsigned-64>>
      end

    apply_codecs(raw, codec.index_codecs, :encode)
  end

  defp embed_index(data_blob, encoded_index, :end),
    do: {:ok, <<data_blob::binary, encoded_index::binary>>}

  defp embed_index(data_blob, encoded_index, :start),
    do: {:ok, <<encoded_index::binary, data_blob::binary>>}

  defp extract_index_and_data(shard_binary, codec) do
    index_len = encoded_index_byte_length(codec)

    case codec.index_location do
      :end ->
        total = byte_size(shard_binary)

        if total < index_len do
          {:error, {:invalid_shard_index, :too_short}}
        else
          data_size = total - index_len
          <<data::binary-size(data_size), index_bin::binary-size(index_len)>> = shard_binary

          with {:ok, entries} <- decode_index(index_bin, codec) do
            {:ok, entries, data}
          end
        end

      :start ->
        if byte_size(shard_binary) < index_len do
          {:error, {:invalid_shard_index, :too_short}}
        else
          <<index_bin::binary-size(index_len), data::binary>> = shard_binary

          with {:ok, entries} <- decode_index(index_bin, codec) do
            {:ok, entries, data}
          end
        end
    end
  end

  defp decode_index(index_bin, codec) do
    with {:ok, raw} <- apply_codecs(index_bin, codec.index_codecs, :decode) do
      expected = raw_index_byte_length(codec.chunk_shape)

      if byte_size(raw) != expected do
        {:error, {:invalid_shard_index, :wrong_size}}
      else
        pairs =
          for <<offset::little-unsigned-64, nbytes::little-unsigned-64 <- raw>>,
            do: {offset, nbytes}

        entries =
          codec.chunk_shape
          |> all_local_indices()
          |> Enum.zip(pairs)
          |> Map.new(fn {local, entry} -> {local, entry} end)

        {:ok, entries}
      end
    end
  end

  defp lookup_entry(entries, local, _chunk_shape) do
    case Map.fetch(entries, local) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, {:invalid_shard_index, :missing_slot}}
    end
  end

  defp empty_entry?(offset, nbytes),
    do: offset == @empty_sentinel and nbytes == @empty_sentinel

  defp all_local_indices(chunk_shape) do
    dims = Tuple.to_list(chunk_shape)

    dims
    |> Enum.map(fn n -> 0..(n - 1)//1 end)
    |> Enum.reduce([[]], fn range, acc ->
      for prefix <- acc, i <- range, do: prefix ++ [i]
    end)
    |> Enum.map(&List.to_tuple/1)
  end

  defp raw_index_byte_length(chunk_shape) do
    count = Enum.reduce(Tuple.to_list(chunk_shape), 1, &*/2)
    count * 16
  end

  defp expand_fixed_index_size(raw_size, codecs) do
    Enum.reduce(normalize_codecs(codecs), raw_size, fn %{name: name}, size ->
      case name do
        "bytes" -> size
        "crc32c" -> size + 4
        _ -> size
      end
    end)
  end

  defp decode_individual_chunk(chunk_data, codecs),
    do: apply_codecs(chunk_data, codecs, :decode)

  defp apply_codecs(data, codecs, :encode) do
    case PipelineV3.parse_codecs(normalize_codecs(codecs)) do
      {:ok, pipeline} -> PipelineV3.encode(data, pipeline)
      error -> error
    end
  end

  defp apply_codecs(data, codecs, :decode) do
    case PipelineV3.parse_codecs(normalize_codecs(codecs)) do
      {:ok, pipeline} -> PipelineV3.decode(data, pipeline)
      error -> error
    end
  end

  defp normalize_codecs(codecs) when is_list(codecs) do
    Enum.map(codecs, fn codec ->
      %{
        name: Map.get(codec, "name") || Map.get(codec, :name),
        configuration: Map.get(codec, "configuration") || Map.get(codec, :configuration, %{})
      }
    end)
  end
end
