defmodule ExZarr.Codecs.ShardingIndexed do
  @moduledoc """
  Zarr `sharding_indexed` codec (accepted specification v1.0).

  Geometry follows the specification:

    * the array's `chunk_grid` chunk shape is the **shard shape** (in elements)
    * the codec's `chunk_shape` is the **inner chunk shape** (in elements)
    * each shard holds `shard_shape / chunk_shape` inner chunks per dimension

  The shard index is a dense C-order array of shape `chunks_per_shard ++ [2]`
  holding little-endian `uint64` `(offset, nbytes)` pairs. Empty inner chunks
  use the sentinel `2^64 - 1` for both values. Offsets are relative to the
  start of the shard object.

  The codec needs the shard shape to know how many inner chunks a shard holds,
  so pass `shard_shape:` to `init/2`. Functions that touch shard bytes return
  `{:error, :shard_shape_required}` when the codec was initialized without it.

  See: https://zarr-specs.readthedocs.io/en/latest/v3/codecs/sharding-indexed/v1.0.html
  """

  alias ExZarr.Codecs.PipelineV3

  @empty_sentinel 0xFFFFFFFFFFFFFFFF

  # Index codecs whose output size is known without looking at the data.
  @fixed_size_index_codecs ["bytes", "crc32c"]

  @type chunk_index :: tuple()
  @type chunk_data :: binary()
  @type chunks_map :: %{chunk_index() => chunk_data()}
  @type shard_binary :: binary()
  @type index_location :: :start | :end

  @type t :: %__MODULE__{
          chunk_shape: tuple(),
          shard_shape: tuple() | nil,
          chunks_per_shard: tuple() | nil,
          codecs: [map()],
          index_codecs: [map()],
          index_location: index_location(),
          pipeline_opts: keyword()
        }

  defstruct [
    :chunk_shape,
    :shard_shape,
    :chunks_per_shard,
    :codecs,
    :index_codecs,
    :index_location,
    pipeline_opts: []
  ]

  @doc """
  Initializes the sharding codec from its `configuration` map.

  ## Options

    * `:shard_shape` - shard shape in elements (the array's chunk grid shape).
      Must be divisible by the inner `chunk_shape` in every dimension.
    * `:dtype` - array data type, passed to the inner codec pipeline.
  """
  @spec init(map(), keyword()) :: {:ok, t()} | {:error, term()}
  def init(config, opts \\ []) when is_map(config) do
    with {:ok, chunk_shape} <- parse_chunk_shape(config),
         {:ok, codecs} <- parse_codecs(config),
         {:ok, index_codecs} <- parse_index_codecs(config),
         :ok <- validate_index_codecs(index_codecs),
         {:ok, index_location} <- parse_index_location(config),
         {:ok, shard_shape, chunks_per_shard} <-
           chunks_per_shard(Keyword.get(opts, :shard_shape), chunk_shape) do
      {:ok,
       %__MODULE__{
         chunk_shape: chunk_shape,
         shard_shape: shard_shape,
         chunks_per_shard: chunks_per_shard,
         codecs: codecs,
         index_codecs: index_codecs,
         index_location: index_location,
         pipeline_opts: pipeline_opts(Keyword.get(opts, :dtype), chunk_shape)
       }}
    end
  end

  @doc """
  Encodes a map of **local** inner-chunk indices into a shard binary.

  Local indices range over `chunks_per_shard`. Chunk data is the raw
  (unencoded) inner chunk; the inner codec pipeline is applied here.
  """
  @spec encode(chunks_map(), t()) :: {:ok, shard_binary()} | {:error, term()}
  def encode(chunks, %__MODULE__{} = codec) when is_map(chunks) do
    with :ok <- require_geometry(codec),
         :ok <- validate_local_keys(chunks, codec.chunks_per_shard),
         {:ok, encoded_chunks} <- encode_individual_chunks(chunks, codec),
         {:ok, data_blob, index_entries} <- pack_chunks(encoded_chunks, codec),
         {:ok, encoded_index} <- encode_index(index_entries, codec) do
      embed_index(data_blob, encoded_index, codec.index_location)
    end
  end

  @doc """
  Decodes one **local** inner chunk from a shard binary.
  """
  @spec decode_chunk(shard_binary(), chunk_index(), t()) ::
          {:ok, chunk_data()} | {:error, term()}
  def decode_chunk(shard_binary, chunk_index, %__MODULE__{} = codec)
      when is_binary(shard_binary) and is_tuple(chunk_index) do
    with :ok <- require_geometry(codec),
         :ok <- validate_local_key(chunk_index, codec.chunks_per_shard),
         {:ok, index_entries} <- extract_index(shard_binary, codec),
         {:ok, entry} <- index_entry(index_entries, chunk_index) do
      if empty_entry?(entry) do
        {:error, {:chunk_not_found, chunk_index}}
      else
        with {:ok, payload} <- slice_payload(shard_binary, entry) do
          decode_chunk_payload(payload, codec)
        end
      end
    end
  end

  @doc """
  Decodes all present (non-sentinel) **local** inner chunks from a shard.
  """
  @spec decode(shard_binary(), t()) :: {:ok, chunks_map()} | {:error, term()}
  def decode(shard_binary, %__MODULE__{} = codec) when is_binary(shard_binary) do
    with :ok <- require_geometry(codec),
         {:ok, index_entries} <- extract_index(shard_binary, codec) do
      codec.chunks_per_shard
      |> all_local_indices()
      |> Enum.reduce_while({:ok, %{}}, fn local, {:ok, acc} ->
        entry = Map.fetch!(index_entries, local)

        with false <- empty_entry?(entry),
             {:ok, payload} <- slice_payload(shard_binary, entry),
             {:ok, decoded} <- decode_chunk_payload(payload, codec) do
          {:cont, {:ok, Map.put(acc, local, decoded)}}
        else
          true -> {:cont, {:ok, acc}}
          error -> {:halt, error}
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
    with :ok <- require_geometry(codec) do
      index_len = encoded_index_byte_length(codec)

      cond do
        shard_size < index_len -> {:error, {:invalid_shard_index, :too_short}}
        codec.index_location == :end -> {:ok, {shard_size - index_len, index_len}}
        true -> {:ok, {0, index_len}}
      end
    end
  end

  @doc """
  Decodes an encoded index binary into a map of local index => `{offset, nbytes}`.
  """
  @spec decode_index_bytes(binary(), t()) :: {:ok, map()} | {:error, term()}
  def decode_index_bytes(index_bin, %__MODULE__{} = codec) when is_binary(index_bin) do
    with :ok <- require_geometry(codec) do
      decode_index(index_bin, codec)
    end
  end

  @doc """
  Looks up a local chunk entry in a decoded index map.
  """
  @spec index_entry(map(), chunk_index()) ::
          {:ok, {non_neg_integer(), non_neg_integer()}} | {:error, term()}
  def index_entry(entries, local_index) when is_map(entries) do
    case Map.fetch(entries, local_index) do
      {:ok, entry} -> {:ok, entry}
      :error -> {:error, {:invalid_shard_index, :missing_slot}}
    end
  end

  @doc """
  Returns true when an index entry is the empty sentinel.
  """
  @spec empty_entry?({integer(), integer()}) :: boolean()
  def empty_entry?({offset, nbytes}),
    do: offset == @empty_sentinel and nbytes == @empty_sentinel

  @doc """
  Returns the encoded index byte length for this codec.

  Raises `ArgumentError` if the codec was initialized without `:shard_shape`.
  """
  @spec encoded_index_byte_length(t()) :: non_neg_integer()
  def encoded_index_byte_length(%__MODULE__{chunks_per_shard: nil}) do
    raise ArgumentError, "sharding codec was initialized without :shard_shape"
  end

  def encoded_index_byte_length(%__MODULE__{} = codec) do
    raw = raw_index_byte_length(codec.chunks_per_shard)

    Enum.reduce(normalize_codecs(codec.index_codecs), raw, fn
      %{name: "crc32c"}, size -> size + 4
      _, size -> size
    end)
  end

  @doc """
  Detects the ExZarr-private shard layout written before 1.2.0.

  Pre-1.2.0 shards stored a sparse index prefixed with a chunk count and framed
  by an 8-byte little-endian index size (trailing for `:end`, leading for
  `:start`). Use this after a standard decode fails to report a migration error
  instead of a generic index error.
  """
  @spec legacy_format?(binary(), index_location()) :: boolean()
  def legacy_format?(shard_binary, index_location \\ :end)

  def legacy_format?(shard_binary, :end) when byte_size(shard_binary) >= 12 do
    total = byte_size(shard_binary)
    prefix_size = total - 8
    <<_::binary-size(^prefix_size), index_size::little-unsigned-64>> = shard_binary

    index_size + 8 <= total and
      legacy_index?(binary_part(shard_binary, total - 8 - index_size, index_size))
  end

  def legacy_format?(<<index_size::little-unsigned-64, rest::binary>>, :start) do
    index_size <= byte_size(rest) and legacy_index?(binary_part(rest, 0, index_size))
  end

  def legacy_format?(_, _), do: false

  @doc false
  def empty_sentinel, do: @empty_sentinel

  @doc """
  Decodes an already-extracted inner-chunk payload through the inner codec pipeline.
  """
  @spec decode_chunk_payload(binary(), t()) :: {:ok, chunk_data()} | {:error, term()}
  def decode_chunk_payload(payload, %__MODULE__{} = codec) when is_binary(payload) do
    apply_codecs(payload, codec.codecs, :decode, codec.pipeline_opts)
  end

  ## Private

  defp require_geometry(%__MODULE__{chunks_per_shard: nil}),
    do: {:error, :shard_shape_required}

  defp require_geometry(_codec), do: :ok

  defp chunks_per_shard(nil, _chunk_shape), do: {:ok, nil, nil}

  defp chunks_per_shard(shard_shape, chunk_shape) when is_list(shard_shape),
    do: chunks_per_shard(List.to_tuple(shard_shape), chunk_shape)

  defp chunks_per_shard(shard_shape, chunk_shape)
       when is_tuple(shard_shape) and tuple_size(shard_shape) == tuple_size(chunk_shape) do
    pairs = Enum.zip(Tuple.to_list(shard_shape), Tuple.to_list(chunk_shape))

    if Enum.all?(pairs, fn {s, c} ->
         is_integer(s) and is_integer(c) and c > 0 and s > 0 and rem(s, c) == 0
       end) do
      {:ok, shard_shape, pairs |> Enum.map(fn {s, c} -> div(s, c) end) |> List.to_tuple()}
    else
      {:error, {:invalid_sharding, %{shard_shape: shard_shape, chunk_shape: chunk_shape}}}
    end
  end

  defp chunks_per_shard(shard_shape, chunk_shape),
    do: {:error, {:invalid_sharding, %{shard_shape: shard_shape, chunk_shape: chunk_shape}}}

  defp pipeline_opts(nil, chunk_shape), do: [shape: chunk_shape]

  defp pipeline_opts(dtype, chunk_shape) do
    [shape: chunk_shape, dtype: dtype, itemsize: ExZarr.DataType.itemsize(dtype)]
  end

  defp parse_chunk_shape(config) do
    case Map.get(config, "chunk_shape") || Map.get(config, :chunk_shape) do
      shape when is_list(shape) -> {:ok, List.to_tuple(shape)}
      shape when is_tuple(shape) -> {:ok, shape}
      _ -> {:error, :missing_chunk_shape}
    end
  end

  defp parse_codecs(%{"codecs" => codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_codecs(%{codecs: codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_codecs(_), do: {:error, :missing_codecs}

  defp parse_index_codecs(%{"index_codecs" => codecs}) when is_list(codecs), do: {:ok, codecs}
  defp parse_index_codecs(%{index_codecs: codecs}) when is_list(codecs), do: {:ok, codecs}

  defp parse_index_codecs(_) do
    {:ok,
     [
       %{"name" => "bytes", "configuration" => %{"endian" => "little"}},
       %{"name" => "crc32c", "configuration" => %{}}
     ]}
  end

  defp parse_index_location(%{"index_location" => "start"}), do: {:ok, :start}
  defp parse_index_location(%{"index_location" => "end"}), do: {:ok, :end}
  defp parse_index_location(%{index_location: :start}), do: {:ok, :start}
  defp parse_index_location(%{index_location: :end}), do: {:ok, :end}
  defp parse_index_location(%{index_location: "start"}), do: {:ok, :start}
  defp parse_index_location(%{index_location: "end"}), do: {:ok, :end}
  defp parse_index_location(_), do: {:ok, :end}

  defp validate_index_codecs([]), do: {:error, {:invalid_index_codecs, :empty}}

  defp validate_index_codecs(codecs) do
    case Enum.find(normalize_codecs(codecs), &(&1.name not in @fixed_size_index_codecs)) do
      nil -> :ok
      %{name: name} -> {:error, {:unsupported_index_codec, name}}
    end
  end

  defp validate_local_keys(chunks, chunks_per_shard) do
    Enum.reduce_while(Map.keys(chunks), :ok, fn key, :ok ->
      case validate_local_key(key, chunks_per_shard) do
        :ok -> {:cont, :ok}
        error -> {:halt, error}
      end
    end)
  end

  defp validate_local_key(index, chunks_per_shard)
       when tuple_size(index) == tuple_size(chunks_per_shard) do
    ok? =
      Enum.zip(Tuple.to_list(index), Tuple.to_list(chunks_per_shard))
      |> Enum.all?(fn {i, n} -> is_integer(i) and i >= 0 and i < n end)

    if ok?, do: :ok, else: {:error, {:invalid_chunk_index, index}}
  end

  defp validate_local_key(index, _), do: {:error, {:invalid_chunk_index, index}}

  defp encode_individual_chunks(chunks, codec) do
    Enum.reduce_while(chunks, {:ok, %{}}, fn {chunk_idx, chunk_data}, {:ok, acc} ->
      case apply_codecs(chunk_data, codec.codecs, :encode, codec.pipeline_opts) do
        {:ok, encoded} -> {:cont, {:ok, Map.put(acc, chunk_idx, encoded)}}
        error -> {:halt, error}
      end
    end)
  end

  defp pack_chunks(encoded_chunks, codec) do
    # Offsets are relative to the full shard. With the index at the start,
    # data begins right after the encoded index.
    data_start =
      if codec.index_location == :start, do: encoded_index_byte_length(codec), else: 0

    {chunks_iodata, entries, _offset} =
      encoded_chunks
      |> Enum.sort()
      |> Enum.reduce({[], %{}, data_start}, fn {idx, bin}, {acc, entries, offset} ->
        size = byte_size(bin)
        {[acc, bin], Map.put(entries, idx, {offset, size}), offset + size}
      end)

    {:ok, IO.iodata_to_binary(chunks_iodata), entries}
  end

  defp encode_index(entries, codec) do
    empty = {@empty_sentinel, @empty_sentinel}

    raw =
      for local <- all_local_indices(codec.chunks_per_shard), into: <<>> do
        {offset, nbytes} = Map.get(entries, local, empty)
        <<offset::little-unsigned-64, nbytes::little-unsigned-64>>
      end

    apply_codecs(raw, codec.index_codecs, :encode, [])
  end

  defp embed_index(data_blob, encoded_index, :end),
    do: {:ok, <<data_blob::binary, encoded_index::binary>>}

  defp embed_index(data_blob, encoded_index, :start),
    do: {:ok, <<encoded_index::binary, data_blob::binary>>}

  defp extract_index(shard_binary, codec) do
    with {:ok, {offset, len}} <- index_byte_range(codec, byte_size(shard_binary)) do
      decode_index(binary_part(shard_binary, offset, len), codec)
    end
  end

  defp slice_payload(shard_binary, {offset, nbytes}) do
    if offset + nbytes > byte_size(shard_binary) do
      {:error, {:invalid_shard_index, :offset_out_of_bounds}}
    else
      {:ok, binary_part(shard_binary, offset, nbytes)}
    end
  end

  defp decode_index(index_bin, codec) do
    with {:ok, raw} <- apply_codecs(index_bin, codec.index_codecs, :decode, []) do
      if byte_size(raw) != raw_index_byte_length(codec.chunks_per_shard) do
        {:error, {:invalid_shard_index, :wrong_size}}
      else
        pairs =
          for <<offset::little-unsigned-64, nbytes::little-unsigned-64 <- raw>>,
            do: {offset, nbytes}

        entries =
          codec.chunks_per_shard
          |> all_local_indices()
          |> Enum.zip(pairs)
          |> Map.new()

        {:ok, entries}
      end
    end
  end

  defp legacy_index?(<<num_chunks::little-unsigned-32, rest::binary>>)
       when num_chunks > 0 and num_chunks < 1_000_000 do
    byte_size(rest) >= num_chunks * 16
  end

  defp legacy_index?(_), do: false

  # C-order enumeration of every local index in the shard grid.
  defp all_local_indices(chunks_per_shard) do
    chunks_per_shard
    |> Tuple.to_list()
    |> Enum.reverse()
    |> Enum.reduce([[]], fn n, acc ->
      for i <- 0..(n - 1)//1, suffix <- acc, do: [i | suffix]
    end)
    |> Enum.map(&List.to_tuple/1)
  end

  defp raw_index_byte_length(chunks_per_shard) do
    chunks_per_shard |> Tuple.to_list() |> Enum.reduce(1, &*/2) |> Kernel.*(16)
  end

  defp apply_codecs(data, codecs, direction, opts) do
    case PipelineV3.parse_codecs(normalize_codecs(codecs)) do
      {:ok, pipeline} when direction == :encode -> PipelineV3.encode(data, pipeline, opts)
      {:ok, pipeline} -> PipelineV3.decode(data, pipeline, opts)
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
