defmodule ExZarr.Codecs.ZigCodecs do
  @moduledoc """
  High-performance compression codec implementations using Zig NIFs.

  This module provides compression and decompression functions for various codecs
  by binding to C libraries through Zig's C interop.

  ## Available Codecs

  - **ZLIB**: Erlang's built-in `:zlib` (always available)
  - **ZSTD**: Zstandard via libzstd (requires system library)
  - **LZ4**: LZ4 via liblz4 (requires system library)
  - **Snappy**: Snappy via libsnappy (requires system library)
  - **Blosc**: Blosc via libblosc (requires system library)
  - **Bzip2**: Bzip2 via libbz2 (requires system library)
  - **CRC32C**: Pure Zig checksum (always available when NIF loads)

  ## Precompiled NIFs

  Hex / Livebook installs download a precompiled NIF for your platform when
  `checksum-ExZarr.Codecs.ZigCodecs.exs` is present (no Zig required).

  Force a local Zig build (developers / CI artifact builders):

      EX_ZARR_BUILD=1 mix compile

  Or:

      config :zigler_precompiled, :force_build, ex_zarr: true

  ## System Library Requirements

  Precompiled and source builds dynamically link compression libraries.
  Install them for codecs other than zlib / crc32c:

  ### macOS
  ```bash
  brew install zstd lz4 snappy c-blosc bzip2
  ```

  ### Ubuntu/Debian
  ```bash
  apt-get install libzstd-dev liblz4-dev libsnappy-dev libblosc-dev libbz2-dev
  ```

  ### Fedora/RHEL
  ```bash
  dnf install zstd-devel lz4-devel snappy-devel blosc-devel bzip2-devel
  ```

  See `docs/PRECOMPILATION.md` for releasing new precompiled artifacts.
  """

  alias ExZarr.Codecs.CompressionConfig

  @version Mix.Project.config()[:version]

  @checksum_file Path.expand(
                   "../../../checksum-ExZarr.Codecs.ZigCodecs.exs",
                   __DIR__
                 )

  # Homebrew / COMPRESSION_*_DIRS / platform defaults (see CompressionConfig)
  @library_dirs CompressionConfig.library_dirs()
  @include_dirs CompressionConfig.include_dirs()

  @force_build System.get_env("EX_ZARR_BUILD") in ["1", "true"] or
                 not File.exists?(@checksum_file) or
                 Application.compile_env(:zigler_precompiled, [:force_build, :ex_zarr], false) ==
                   true

  use ZiglerPrecompiled,
    otp_app: :ex_zarr,
    base_url: "https://github.com/AnimaLogica/ExZarr/releases/download/v#{@version}",
    version: @version,
    force_build: @force_build,
    targets: ~w(
      x86_64-linux-gnu
      aarch64-linux-gnu
      aarch64-macos-none
      x86_64-windows-gnu
    ),
    zig_code_path: "zig_codecs.zig",
    optimize: :env,
    c: [
      include_dirs: @include_dirs,
      library_dirs: @library_dirs,
      link_lib: [
        {:system, "zstd"},
        {:system, "lz4"},
        {:system, "snappy"},
        {:system, "blosc"},
        # Use dynamic linking for bzip2 to avoid PIC issues on Linux
        {:system, "bz2"}
      ]
    ],
    nifs: [
      zstd_compress: 2,
      zstd_decompress: 1,
      lz4_compress: 1,
      lz4_decompress: 2,
      snappy_compress: 1,
      snappy_decompress: 1,
      blosc_compress: 2,
      blosc_decompress: 1,
      bzip2_compress: 2,
      bzip2_decompress: 2,
      crc32c_encode: 1,
      crc32c_decode: 1
    ]

  @doc """
  Compresses data using ZLIB.
  Uses Erlang's battle-tested :zlib for maximum compatibility.
  """
  def zlib_compress(data) when is_binary(data) do
    compressed = :zlib.compress(data)
    {:ok, compressed}
  rescue
    e -> {:error, {:zlib_compress_failed, e}}
  end

  @doc """
  Decompresses ZLIB data.
  """
  def zlib_decompress(data) when is_binary(data) do
    decompressed = :zlib.uncompress(data)
    {:ok, decompressed}
  rescue
    e -> {:error, {:zlib_decompress_failed, e}}
  end
end
