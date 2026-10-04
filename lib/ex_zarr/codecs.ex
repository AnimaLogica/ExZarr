defmodule ExZarr.Codecs do
  @moduledoc """
  Compression and decompression codecs for Zarr arrays.

  Supports both built-in and custom codecs through an extensible codec registry.

  ## Built-in Codecs

  - `:none` - No compression
  - `:zlib` - zlib via Erlang's built-in `:zlib`
  - `:zstd` - Zstandard frames
  - `:lz4` - LZ4 block with a 4-byte little-endian size prefix (numcodecs `LZ4`)
  - `:snappy` - Raw Snappy
  - `:blosc` - Blosc1 chunks (c-blosc 1.x / numcodecs `Blosc` / Zarr `blosc`)
  - `:bzip2` - bzip2 stream (numcodecs `BZ2`)
  - `:crc32c` - Appends / verifies a little-endian CRC32C (Zarr v3 `crc32c`)

  Everything except `:none` and `:zlib` is provided by
  [ExCodecs](https://hex.pm/packages/ex_codecs): pure-Rust NIFs that ship
  precompiled for Linux (glibc and musl), macOS and Windows. No system
  libraries or compilers are needed.

  ## Compression Performance

  - `:none` - Fastest, largest
  - `:lz4` / `:snappy` - Very fast, moderate ratio
  - `:zlib` - Balanced
  - `:zstd` - High ratio, fast decompression, configurable level
  - `:blosc` - Shuffle filters plus a compressor; strong on numeric data
  - `:bzip2` - High ratio, slow
  - `:crc32c` - Integrity check, not compression (4 bytes overhead)

  ## Options

  `compress/3` accepts a keyword list (or map):

  - `:level` - compression level (`:zlib` 0-9, `:zstd` 1-22, `:blosc` 0-9,
    `:bzip2` 1-9)
  - `:cname`, `:shuffle`, `:typesize` - `:blosc` only; defaults `:blosclz`,
    `:byte` and `1`

  Decompressed chunks are capped at 256 MiB as protection against
  decompression bombs. Raise the cap for larger chunks:

      config :ex_zarr, max_chunk_bytes: 1_073_741_824

  ## Compatibility

  `:lz4` and `:bzip2` data written by ExZarr 1.1 (an 8-byte size prefix) is
  still read; new data uses the numcodecs formats, so zarr-python can read it.

  ## Custom Codecs

  ExZarr supports custom codecs through the `ExZarr.Codecs.Codec` behavior.
  Implement the behavior and register your codec:

      defmodule MyApp.CustomCodec do
        @behaviour ExZarr.Codecs.Codec

        def codec_id, do: :my_codec
        def codec_info, do: %{name: "My Codec", version: "1.0", type: :compression}
        def available?, do: true
        def encode(data, _opts), do: {:ok, data}
        def decode(data, _opts), do: {:ok, data}
      end

      # Register the codec
      ExZarr.Codecs.register_codec(MyApp.CustomCodec)

      # Use it like built-in codecs
      {:ok, encoded} = ExZarr.Codecs.compress(data, :my_codec)

  See `ExZarr.Codecs.Codec` for full documentation on implementing custom codecs.

  ## Examples

      # Compress data with zlib (always available)
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)

      # Decompress data
      {:ok, original} = ExZarr.Codecs.decompress(compressed, :zlib)

      # Use zstd with compression level
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zstd, level: 5)

      # Use blosc (excellent for numerical data)
      {:ok, compressed} = ExZarr.Codecs.compress(float_data, :blosc, level: 9)

      # Use CRC32C checksum (adds 4-byte checksum for data integrity)
      {:ok, checksummed} = ExZarr.Codecs.compress(data, :crc32c)

      # No compression
      {:ok, data} = ExZarr.Codecs.compress("hello", :none)
      # data == "hello"

      # Check codec availability
      ExZarr.Codecs.codec_available?(:zstd) # => true
  """

  alias ExZarr.Codecs.Registry

  # Changed from fixed atoms to allow custom codecs
  @type codec :: atom()
  @type codec_module :: module()

  @doc """
  Compresses data using the specified codec.

  Takes binary data and compresses it using the chosen compression algorithm.
  The `:none` codec returns the data unchanged. Other codecs apply compression
  and return the compressed binary.

  ## Parameters

  - `data` - Binary data to compress
  - `codec` - Compression codec (`:none`, `:zlib`, `:zstd`, `:lz4`, `:snappy`, `:blosc`, `:bzip2`, or `:crc32c`)
  - `opts` - Optional keyword list (or map) with compression options:
    - `:level` - Compression level (codec-specific, typically 1-9)
    - `:cname`, `:shuffle`, `:typesize` - `:blosc` only (defaults `:blosclz`,
      `:byte`, `1`)

  ## Examples

      # Compress with zlib
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)

      # Compress with zstd at level 5
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zstd, level: 5)

      # No compression
      {:ok, same} = ExZarr.Codecs.compress("hello", :none)
      # same == "hello"

      # Compress binary data
      data = :crypto.strong_rand_bytes(1000)
      {:ok, compressed} = ExZarr.Codecs.compress(data, :zlib)

  ## Returns

  - `{:ok, compressed_binary}` on success
  - `{:error, {:unsupported_codec, codec}}` if codec is not available
  - `{:error, {:compression_failed, reason}}` if compression fails
  """
  @spec compress(binary(), codec(), keyword()) :: {:ok, binary()} | {:error, term()}
  def compress(data, codec, opts \\ [])

  # First try to use custom codec from registry
  def compress(data, codec, opts) when is_map(opts), do: compress(data, codec, Map.to_list(opts))

  def compress(data, codec, opts) when is_binary(data) and is_atom(codec) do
    case Registry.get(codec) do
      {:ok, builtin} when is_atom(builtin) ->
        handle_codec_compression(builtin, data, opts)

      {:error, :not_found} ->
        {:error, {:unsupported_codec, codec}}
    end
  end

  defp handle_codec_compression(builtin, data, opts) when is_atom(builtin) do
    case builtin do
      codec
      when codec in [
             :builtin_none,
             :builtin_zlib,
             :builtin_crc32c,
             :builtin_zstd,
             :builtin_lz4,
             :builtin_snappy,
             :builtin_blosc,
             :builtin_bzip2
           ] ->
        codec_name =
          builtin |> Atom.to_string() |> String.replace_prefix("builtin_", "") |> String.to_atom()

        compress_builtin(data, codec_name, opts)

      custom_module ->
        # Custom codec module
        custom_module.encode(data, opts)
    end
  end

  # Built-in codec implementations. zlib uses Erlang's :zlib; everything else
  # goes through ExCodecs (pure-Rust NIFs, precompiled).
  defp compress_builtin(data, :none, _opts), do: {:ok, data}

  defp compress_builtin(data, :zlib, opts) do
    case Keyword.get(opts, :level) do
      nil -> {:ok, :zlib.compress(data)}
      level -> {:ok, zlib_compress(data, level)}
    end
  rescue
    e -> {:error, {:compression_failed, e}}
  end

  defp compress_builtin(data, :zstd, opts),
    do: ex_codecs_encode(:zstd, data, level: Keyword.get(opts, :level, 3))

  # numcodecs LZ4 format: 4-byte little-endian size + LZ4 block.
  defp compress_builtin(data, :lz4, _opts), do: ex_codecs_encode(:lz4, data, [])

  defp compress_builtin(data, :snappy, _opts), do: ex_codecs_encode(:snappy, data, [])

  # Blosc1 chunk, readable by c-blosc 1.x / numcodecs / zarr-python. Defaults
  # match ExZarr 1.1 (BloscLZ, byte shuffle, typesize 1).
  defp compress_builtin(data, :blosc, opts) do
    ex_codecs_encode(:blosc, data,
      cname: Keyword.get(opts, :cname, :blosclz),
      clevel: Keyword.get(opts, :level, 5),
      shuffle: Keyword.get(opts, :shuffle, :byte),
      typesize: Keyword.get(opts, :typesize, 1)
    )
  end

  # Plain bzip2 stream (numcodecs BZ2 format).
  defp compress_builtin(data, :bzip2, opts),
    do: ex_codecs_encode(:bzip2, data, block_size: Keyword.get(opts, :level, 9))

  # Appends a little-endian CRC32C.
  defp compress_builtin(data, :crc32c, _opts) do
    case ExCodecs.encode(:crc32c, data) do
      {:ok, checksummed} -> {:ok, checksummed}
      {:error, error} -> {:error, {:checksum_failed, error.reason}}
    end
  end

  defp zlib_compress(data, level) do
    z = :zlib.open()

    try do
      :ok = :zlib.deflateInit(z, level)
      compressed = :zlib.deflate(z, data, :finish)
      :ok = :zlib.deflateEnd(z)
      IO.iodata_to_binary(compressed)
    after
      :zlib.close(z)
    end
  end

  defp ex_codecs_encode(codec, data, opts) do
    case ExCodecs.encode(codec, data, opts) do
      {:ok, compressed} -> {:ok, compressed}
      {:error, error} -> {:error, {:compression_failed, error.reason}}
    end
  end

  @doc """
  Decompresses data using the specified codec.

  Takes compressed binary data and decompresses it using the chosen algorithm.
  The codec must match the one used for compression. The `:none` codec returns
  the data unchanged.

  ## Parameters

  - `data` - Compressed binary data
  - `codec` - Compression codec (`:none`, `:zlib`, `:zstd`, `:lz4`, `:snappy`, `:blosc`, `:bzip2`, or `:crc32c`)

  ## Examples

      # Compress and decompress
      {:ok, compressed} = ExZarr.Codecs.compress("hello world", :zlib)
      {:ok, original} = ExZarr.Codecs.decompress(compressed, :zlib)
      # original == "hello world"

      # No decompression needed
      {:ok, same} = ExZarr.Codecs.decompress("hello", :none)
      # same == "hello"

  ## Returns

  - `{:ok, decompressed_binary}` on success
  - `{:error, {:unsupported_codec, codec}}` if codec is not available
  - `{:error, {:decompression_failed, reason}}` if decompression fails

  ## Errors

  Decompression will fail if:
  - The data is not validly compressed with the specified codec
  - The data is corrupted
  - The wrong codec is specified

  ## Notes

  `:lz4` and `:bzip2` also read the 8-byte size-prefixed layout written by
  ExZarr 1.1.
  """
  @spec decompress(binary(), codec()) :: {:ok, binary()} | {:error, term()}

  # First try to use custom codec from registry
  def decompress(data, codec) when is_binary(data) and is_atom(codec) do
    case Registry.get(codec) do
      {:ok, builtin} when is_atom(builtin) ->
        handle_codec_decompression(builtin, data)

      {:error, :not_found} ->
        {:error, {:unsupported_codec, codec}}
    end
  end

  defp handle_codec_decompression(builtin, data) when is_atom(builtin) do
    case builtin do
      codec
      when codec in [
             :builtin_none,
             :builtin_zlib,
             :builtin_crc32c,
             :builtin_zstd,
             :builtin_lz4,
             :builtin_snappy,
             :builtin_blosc,
             :builtin_bzip2
           ] ->
        codec_name =
          builtin |> Atom.to_string() |> String.replace_prefix("builtin_", "") |> String.to_atom()

        decompress_builtin(data, codec_name)

      custom_module ->
        # Custom codec module
        custom_module.decode(data, [])
    end
  end

  # Built-in codec implementations
  defp decompress_builtin(data, :none), do: {:ok, data}

  defp decompress_builtin(data, :zlib) do
    {:ok, :zlib.uncompress(data)}
  rescue
    e -> {:error, {:decompression_failed, e}}
  end

  defp decompress_builtin(data, :zstd), do: ex_codecs_decode(:zstd, data)

  defp decompress_builtin(data, :lz4) do
    case ex_codecs_decode(:lz4, data) do
      {:ok, decompressed} -> {:ok, decompressed}
      error -> decode_legacy_lz4(data, error)
    end
  end

  defp decompress_builtin(data, :snappy), do: ex_codecs_decode(:snappy, data)

  # Reads Blosc1 (and Blosc2) chunks; the compressor settings are in the header.
  defp decompress_builtin(data, :blosc), do: ex_codecs_decode(:blosc, data)

  defp decompress_builtin(data, :bzip2) do
    case ex_codecs_decode(:bzip2, data) do
      {:ok, decompressed} -> {:ok, decompressed}
      error -> decode_legacy_bzip2(data, error)
    end
  end

  # Verifies and strips a trailing little-endian CRC32C.
  defp decompress_builtin(data, :crc32c) do
    case ExCodecs.decode(:crc32c, data) do
      {:ok, validated} -> {:ok, validated}
      {:error, error} -> {:error, {:checksum_validation_failed, crc32c_reason(error.reason)}}
    end
  end

  # ExZarr 1.1 wrote LZ4 as an 8-byte native-endian size followed by a raw LZ4
  # block. A valid block never starts with a zero token after a 4-byte size, so
  # the standard decode fails on this layout and we retry with the 4-byte
  # prefix numcodecs (and ExCodecs) use.
  defp decode_legacy_lz4(<<size::64-unsigned-native, block::binary>>, _error)
       when size <= 0xFFFFFFFF do
    case ex_codecs_decode(:lz4, <<size::32-little, block::binary>>) do
      {:ok, decompressed} when byte_size(decompressed) == size -> {:ok, decompressed}
      _ -> {:error, {:decompression_failed, :invalid_lz4_format}}
    end
  end

  defp decode_legacy_lz4(_data, error), do: error

  # ExZarr 1.1 wrote bzip2 as an 8-byte native-endian size followed by the stream.
  defp decode_legacy_bzip2(<<size::64-unsigned-native, "BZh", _::binary>> = data, _error) do
    <<_::binary-size(8), stream::binary>> = data

    case ex_codecs_decode(:bzip2, stream) do
      {:ok, decompressed} when byte_size(decompressed) == size -> {:ok, decompressed}
      _ -> {:error, {:decompression_failed, :invalid_bzip2_format}}
    end
  end

  defp decode_legacy_bzip2(_data, error), do: error

  # Keep the error atoms ExZarr has always returned for CRC32C.
  defp crc32c_reason(:truncated_input), do: :crc32c_invalid_data
  defp crc32c_reason(:checksum_mismatch), do: :crc32c_checksum_mismatch
  defp crc32c_reason(reason), do: reason

  defp ex_codecs_decode(codec, data) do
    case ExCodecs.decode(codec, data, max_output_size: max_chunk_bytes()) do
      {:ok, decompressed} -> {:ok, decompressed}
      {:error, error} -> {:error, {:decompression_failed, error.reason}}
    end
  end

  # Upper bound on one decoded chunk, guarding against decompression bombs.
  defp max_chunk_bytes, do: Application.get_env(:ex_zarr, :max_chunk_bytes, 256 * 1024 * 1024)

  @doc """
  Returns the list of available codecs.

  This function checks which codecs are available at runtime. `:none` and
  `:zlib` are always available; the others are available whenever the
  ExCodecs NIF is loaded.

  ## Examples

      ExZarr.Codecs.available_codecs()
      # => [:none, :zlib, :crc32c, :zstd, :lz4, :snappy, :blosc, :bzip2]

  ## Returns

  List of codec atoms that can be used with `compress/3` and `decompress/2`.
  """
  @spec available_codecs() :: [codec(), ...]
  def available_codecs do
    # Use the registry's available function which checks all codecs
    Registry.available()
  end

  @doc """
  Checks if a codec is available for use.

  Returns `true` if the codec can be used with `compress/3` and `decompress/2`,
  `false` otherwise.

  Custom codecs answer through their `available?/0` callback.

  ## Examples

      ExZarr.Codecs.codec_available?(:zlib)
      # => true

      ExZarr.Codecs.codec_available?(:zstd)
      # => true

      ExZarr.Codecs.codec_available?(:unknown)
      # => false

  ## Parameters

  - `codec` - Codec atom to check

  ## Returns

  Boolean indicating codec availability.
  """
  @spec codec_available?(codec()) :: boolean()
  def codec_available?(codec) when is_atom(codec) do
    case Registry.get(codec) do
      {:ok, :builtin_none} ->
        true

      {:ok, :builtin_zlib} ->
        true

      {:ok, :builtin_crc32c} ->
        nif_codec_available?(:crc32c)

      {:ok, :builtin_zstd} ->
        nif_codec_available?(:zstd)

      {:ok, :builtin_lz4} ->
        nif_codec_available?(:lz4)

      {:ok, :builtin_snappy} ->
        nif_codec_available?(:snappy)

      {:ok, :builtin_blosc} ->
        nif_codec_available?(:blosc)

      {:ok, :builtin_bzip2} ->
        nif_codec_available?(:bzip2)

      {:ok, codec_module} ->
        # Custom codec - call its available? callback
        try do
          codec_module.available?()
        rescue
          _ -> false
        end

      {:error, :not_found} ->
        false
    end
  end

  # The ExCodecs NIF ships precompiled for every supported target; a codec is
  # unavailable only if the NIF failed to load.
  defp nif_codec_available?(codec), do: codec in ExCodecs.available_codecs()

  # === Custom Codec Support ===

  @doc """
  Registers a custom codec.

  The codec module must implement the `ExZarr.Codecs.Codec` behavior.

  ## Examples

      defmodule MyApp.CustomCodec do
        @behaviour ExZarr.Codecs.Codec

        def codec_id, do: :my_codec
        def codec_info, do: %{name: "My Codec", version: "1.0", type: :compression, description: "..."}
        def available?, do: true
        def encode(data, _opts), do: {:ok, my_encode(data)}
        def decode(data, _opts), do: {:ok, my_decode(data)}
      end

      ExZarr.Codecs.register_codec(MyApp.CustomCodec)
      {:ok, encoded} = ExZarr.Codecs.compress(data, :my_codec)

  ## Options

  - `:force` - Overwrite existing codec with same ID (default: false)

  ## Returns

  - `:ok` - Codec registered successfully
  - `{:error, :already_registered}` - Codec ID already in use
  - `{:error, :invalid_codec}` - Module doesn't implement Codec behavior
  """
  @spec register_codec(codec_module(), keyword()) :: :ok | {:error, term()}
  def register_codec(codec_module, opts \\ []) do
    Registry.register(codec_module, opts)
  end

  @doc """
  Unregisters a custom codec.

  Built-in codecs cannot be unregistered.

  ## Examples

      ExZarr.Codecs.unregister_codec(:my_codec)

  ## Returns

  - `:ok` - Codec unregistered successfully
  - `{:error, :not_found}` - Codec not registered
  - `{:error, :cannot_unregister_builtin}` - Cannot unregister built-in codec
  """
  @spec unregister_codec(codec()) :: :ok | {:error, term()}
  def unregister_codec(codec_id) do
    Registry.unregister(codec_id)
  end

  @doc """
  Gets information about a codec.

  Returns metadata including name, version, type, and description.

  ## Examples

      {:ok, info} = ExZarr.Codecs.codec_info(:zstd)
      # => %{
      #   name: "Zstandard",
      #   version: "1.0.0",
      #   type: :compression,
      #   description: "Zstandard compression algorithm"
      # }

  ## Returns

  - `{:ok, map()}` - Codec information
  - `{:error, :not_found}` - Codec not registered
  """
  @spec codec_info(codec()) :: {:ok, map()} | {:error, :not_found}
  def codec_info(codec_id) do
    Registry.info(codec_id)
  end

  @doc """
  Lists all registered codec IDs.

  Includes both built-in and custom codecs, regardless of availability.

  ## Examples

      ExZarr.Codecs.list_codecs()
      # => [:none, :zlib, :crc32c, :zstd, :lz4, :my_codec]
  """
  @spec list_codecs() :: [codec()]
  def list_codecs do
    Registry.list()
  end
end
