defmodule ExZarr.Codecs.CompressorConfig do
  @moduledoc """
  Validates `compressor_config:` options and maps them to and from Zarr
  metadata.

  `ExZarr.create/1` accepts a compressor and its settings:

      ExZarr.create(shape: {1000}, chunks: {100}, compressor: :zstd, compressor_config: [level: 9])

  Supported settings per built-in compressor:

  | Compressor | Settings |
  |------------|----------|
  | `:zlib` | `level` 0-9 (default 6; 5 for the v3 `gzip` codec) |
  | `:gzip` (Zarr v3 only) | `level` 0-9 (default 5) |
  | `:zstd` | `level` 1-22 (default 3) |
  | `:bzip2` | `level` 1-9 (default 9) |
  | `:blosc` | `cname` (`:blosclz`, `:lz4`, `:lz4hc`, `:zlib`, `:zstd`; default `:blosclz`), `level` 0-9 (default 5; `clevel` also accepted), `shuffle` (`:none`, `:byte`, `:bit`; default `:byte`), `typesize` 1-255 (default 1) |
  | `:lz4`, `:snappy`, `:crc32c`, `:none` | none |

  Settings for custom codecs are passed through to the codec unchanged.

  For Zarr v2 the settings are stored in `.zarray` in numcodecs form and read
  back on open, so later writes use the same settings. numcodecs' `Blosc` has
  no `typesize` field; a configured Blosc `typesize` applies to the creating
  process only (reopened arrays use the default). For Zarr v3 the settings
  become the compressor codec's `configuration` in `zarr.json`.
  """

  @blosc_cnames [:blosclz, :lz4, :lz4hc, :zlib, :zstd]
  @blosc_shuffles [:none, :byte, :bit]
  @no_settings [:none, :lz4, :snappy, :crc32c]

  @doc """
  Validates `config` (a keyword list or map) for `compressor`.

  Returns `{:ok, keyword}` with normalised keys and values, or
  `{:error, {:invalid_compressor_config, compressor, reason}}`.

  ## Examples

      iex> ExZarr.Codecs.CompressorConfig.normalize(:zstd, level: 9)
      {:ok, [level: 9]}

      iex> ExZarr.Codecs.CompressorConfig.normalize(:blosc, %{cname: "zstd", clevel: 7})
      {:ok, [cname: :zstd, level: 7]}

      iex> ExZarr.Codecs.CompressorConfig.normalize(:lz4, level: 1)
      {:error, {:invalid_compressor_config, :lz4, {:unknown_option, :level}}}
  """
  @spec normalize(atom(), keyword() | map() | nil) ::
          {:ok, keyword()} | {:error, {:invalid_compressor_config, atom(), term()}}
  def normalize(_compressor, nil), do: {:ok, []}

  def normalize(compressor, config) when is_map(config),
    do: normalize(compressor, Map.to_list(config))

  def normalize(compressor, config) when is_list(config) do
    if Keyword.keyword?(config) do
      config
      |> Enum.reduce_while({:ok, []}, fn {key, value}, {:ok, acc} ->
        case option(compressor, key, value) do
          {:ok, {k, v}} -> {:cont, {:ok, Keyword.put(acc, k, v)}}
          {:error, reason} -> {:halt, {:error, {:invalid_compressor_config, compressor, reason}}}
        end
      end)
      |> case do
        {:ok, opts} -> {:ok, Enum.reverse(opts)}
        error -> error
      end
    else
      {:error, {:invalid_compressor_config, compressor, :not_a_keyword_list}}
    end
  end

  def normalize(compressor, other),
    do: {:error, {:invalid_compressor_config, compressor, {:not_a_keyword_list, other}}}

  # String keys (from JSON) become atoms only when they are known options.
  defp option(compressor, key, value) when is_binary(key) do
    case key do
      k when k in ~w(level clevel cname shuffle typesize) ->
        option(compressor, String.to_atom(k), value)

      _ ->
        {:error, {:unknown_option, key}}
    end
  end

  defp option(compressor, :level, l)
       when compressor in [:zlib, :gzip] and is_integer(l) and l in 0..9,
       do: {:ok, {:level, l}}

  defp option(:zstd, :level, l) when is_integer(l) and l in 1..22, do: {:ok, {:level, l}}
  defp option(:bzip2, :level, l) when is_integer(l) and l in 1..9, do: {:ok, {:level, l}}

  defp option(:blosc, key, l) when key in [:level, :clevel] and is_integer(l) and l in 0..9,
    do: {:ok, {:level, l}}

  defp option(:blosc, :cname, cname) when is_binary(cname) do
    case Enum.find(@blosc_cnames, &(Atom.to_string(&1) == cname)) do
      nil -> {:error, {:invalid_value, :cname, cname}}
      atom -> {:ok, {:cname, atom}}
    end
  end

  defp option(:blosc, :cname, cname) when cname in @blosc_cnames, do: {:ok, {:cname, cname}}
  defp option(:blosc, :shuffle, s) when s in @blosc_shuffles, do: {:ok, {:shuffle, s}}

  defp option(:blosc, :typesize, t) when is_integer(t) and t in 1..255,
    do: {:ok, {:typesize, t}}

  defp option(compressor, key, value)
       when compressor in [:zlib, :gzip, :zstd, :bzip2, :blosc] and
              key in [:level, :clevel, :cname, :shuffle, :typesize] do
    if key in allowed(compressor),
      do: {:error, {:invalid_value, key, value}},
      else: {:error, {:unknown_option, key}}
  end

  defp option(compressor, key, _value) when compressor in [:zlib, :gzip, :zstd, :bzip2, :blosc],
    do: {:error, {:unknown_option, key}}

  defp option(compressor, key, _value) when compressor in @no_settings,
    do: {:error, {:unknown_option, key}}

  # Custom codec: pass through.
  defp option(_compressor, key, value) when is_atom(key), do: {:ok, {key, value}}
  defp option(_compressor, key, _value), do: {:error, {:unknown_option, key}}

  defp allowed(:blosc), do: [:level, :clevel, :cname, :shuffle, :typesize]
  defp allowed(_), do: [:level]

  @doc """
  numcodecs compressor JSON (Zarr v2 `.zarray`) for `compressor` and its
  normalised options. Unset values are the ones ExZarr uses by default.

  ## Examples

      iex> ExZarr.Codecs.CompressorConfig.to_numcodecs(:zstd, level: 7)
      %{id: "zstd", level: 7}

      iex> ExZarr.Codecs.CompressorConfig.to_numcodecs(:blosc, cname: :lz4, shuffle: :bit)
      %{id: "blosc", cname: "lz4", clevel: 5, shuffle: 2, blocksize: 0}
  """
  @spec to_numcodecs(atom(), keyword()) :: map() | nil
  def to_numcodecs(:none, _opts), do: nil
  def to_numcodecs(:zlib, opts), do: %{id: "zlib", level: Keyword.get(opts, :level, 6)}
  def to_numcodecs(:zstd, opts), do: %{id: "zstd", level: Keyword.get(opts, :level, 3)}
  def to_numcodecs(:bzip2, opts), do: %{id: "bz2", level: Keyword.get(opts, :level, 9)}
  def to_numcodecs(:lz4, _opts), do: %{id: "lz4", acceleration: 1}

  def to_numcodecs(:blosc, opts) do
    %{
      id: "blosc",
      cname: Atom.to_string(Keyword.get(opts, :cname, :blosclz)),
      clevel: Keyword.get(opts, :level, 5),
      shuffle: shuffle_to_int(Keyword.get(opts, :shuffle, :byte)),
      blocksize: 0
    }
  end

  def to_numcodecs(compressor, opts) when is_atom(compressor) do
    opts
    |> Enum.filter(fn {_k, v} -> is_integer(v) or is_binary(v) or is_atom(v) end)
    |> Map.new(fn {k, v} ->
      {k, if(is_atom(v) and not is_boolean(v), do: Atom.to_string(v), else: v)}
    end)
    |> Map.put(:id, Atom.to_string(compressor))
  end

  @doc """
  Reads a numcodecs compressor JSON map (atom or string keys) back into an
  ExZarr compressor and options.

  ## Examples

      iex> ExZarr.Codecs.CompressorConfig.from_numcodecs(%{"id" => "bz2", "level" => 5})
      {:bzip2, [level: 5]}

      iex> ExZarr.Codecs.CompressorConfig.from_numcodecs(%{id: "blosc", cname: "zstd", clevel: 3, shuffle: 2, blocksize: 0})
      {:blosc, [cname: :zstd, level: 3, shuffle: :bit]}
  """
  @spec from_numcodecs(map() | nil) :: {atom(), keyword()}
  def from_numcodecs(nil), do: {:none, []}

  def from_numcodecs(json) when is_map(json) do
    get = fn key -> Map.get(json, key, Map.get(json, Atom.to_string(key))) end

    case get.(:id) do
      # numcodecs calls bzip2 "bz2"; ExZarr 1.1 wrote "bzip2".
      id when id in ["bz2", "bzip2"] -> {:bzip2, level_opts(get.(:level), 1..9)}
      "zlib" -> {:zlib, level_opts(get.(:level), 0..9)}
      "zstd" -> {:zstd, level_opts(get.(:level), 1..22)}
      "lz4" -> {:lz4, []}
      "blosc" -> {:blosc, blosc_opts(get)}
      id when is_binary(id) -> {String.to_atom(id), []}
      _ -> {:none, []}
    end
  end

  def from_numcodecs(_), do: {:none, []}

  defp level_opts(level, range) when is_integer(level) do
    if level in range, do: [level: level], else: []
  end

  defp level_opts(_level, _range), do: []

  defp blosc_opts(get) do
    [
      cname: blosc_cname(get.(:cname)),
      level: blosc_level(get.(:clevel)),
      shuffle: shuffle_from_int(get.(:shuffle))
    ]
    |> Enum.reject(fn {_k, v} -> is_nil(v) end)
  end

  defp blosc_cname(cname) when is_binary(cname) do
    case option(:blosc, :cname, cname) do
      {:ok, {:cname, atom}} -> atom
      _ -> nil
    end
  end

  defp blosc_cname(_), do: nil

  defp blosc_level(level) when is_integer(level) and level in 0..9, do: level
  defp blosc_level(_), do: nil

  @doc """
  Zarr v3 compressor codec configuration for `compressor` and its options.

  ## Examples

      iex> ExZarr.Codecs.CompressorConfig.to_v3(:zstd, level: 9)
      %{name: "zstd", configuration: %{level: 9}}

      iex> ExZarr.Codecs.CompressorConfig.to_v3(:snappy, [])
      nil
  """
  @spec to_v3(atom(), keyword()) :: map() | nil
  # zlib arrays use the v3 gzip codec.
  def to_v3(compressor, opts) when compressor in [:zlib, :gzip],
    do: %{name: "gzip", configuration: %{level: Keyword.get(opts, :level, 5)}}

  def to_v3(:zstd, opts),
    do: %{name: "zstd", configuration: %{level: Keyword.get(opts, :level, 5)}}

  def to_v3(:lz4, _opts), do: %{name: "lz4", configuration: %{}}

  def to_v3(:bzip2, opts),
    do: %{name: "bz2", configuration: Map.new(Keyword.take(opts, [:level]))}

  def to_v3(:crc32c, _opts), do: %{name: "crc32c", configuration: %{}}

  def to_v3(:blosc, opts) do
    config =
      Enum.reduce(opts, %{}, fn
        {:cname, c}, acc -> Map.put(acc, :cname, Atom.to_string(c))
        {:level, l}, acc -> Map.put(acc, :clevel, l)
        {:shuffle, s}, acc -> Map.put(acc, :shuffle, shuffle_to_v3(s))
        {:typesize, t}, acc -> Map.put(acc, :typesize, t)
        _, acc -> acc
      end)

    %{name: "blosc", configuration: config}
  end

  def to_v3(_compressor, _opts), do: nil

  defp shuffle_to_int(:none), do: 0
  defp shuffle_to_int(:byte), do: 1
  defp shuffle_to_int(:bit), do: 2

  defp shuffle_from_int(0), do: :none
  defp shuffle_from_int(1), do: :byte
  defp shuffle_from_int(2), do: :bit
  defp shuffle_from_int(_), do: nil

  defp shuffle_to_v3(:none), do: "noshuffle"
  defp shuffle_to_v3(:byte), do: "shuffle"
  defp shuffle_to_v3(:bit), do: "bitshuffle"
end
