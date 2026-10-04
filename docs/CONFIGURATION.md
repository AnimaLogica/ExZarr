# Configuration Guide

ExZarr needs no build-time configuration: it has no native code of its own,
and its compression codecs come from [ExCodecs](https://hex.pm/packages/ex_codecs),
which downloads precompiled NIFs for your platform. This guide lists the
runtime settings ExZarr reads.

## Application settings

Set these in `config/config.exs` (or `runtime.exs`):

```elixir
config :ex_zarr,
  default_zarr_version: 2,
  max_chunk_bytes: 256 * 1024 * 1024,
  range_read_concurrency: 4,
  range_read_timeout: 60_000,
  custom_codecs: [MyApp.MyCodec],
  custom_storage_backends: [MyApp.MyBackend]
```

| Setting | Default | Meaning |
|---------|---------|---------|
| `:default_zarr_version` | `2` | Zarr version for `ExZarr.create/1` and `ExZarr.Nx` when no `zarr_version:` option is given (`2` or `3`). |
| `:max_chunk_bytes` | `268_435_456` (256 MiB) | Largest decompressed chunk any codec may produce. Protects against decompression bombs; raise it if your chunks are bigger. Blosc chunks are additionally capped at 1 GiB by the Blosc format. |
| `:range_read_concurrency` | `4` | Parallel inner-chunk range requests per shard when reading sharded v3 arrays from range-capable storage. |
| `:range_read_timeout` | `60_000` | Timeout in milliseconds for each of those range requests. A timed-out read falls back to downloading the whole shard. |
| `:custom_codecs` | `[]` | Codec modules (implementing `ExZarr.Codecs.Codec`) registered at startup. See `ExZarr.Codecs.Registry`. |
| `:custom_storage_backends` | `[]` | Storage backend modules (implementing `ExZarr.Storage.Backend`) registered at startup. See the [custom storage backend guide](guides/custom_storage_backend.md). |

## Compressor settings

Compressor settings are per array, not application config. Pass them to
`ExZarr.create/1`:

```elixir
ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  compressor: :blosc,
  compressor_config: [cname: :zstd, level: 5, shuffle: :bit, typesize: 8]
)
```

See `ExZarr.Codecs.CompressorConfig` for the settings each compressor accepts.

## Codec availability

All built-in codecs are available on every platform ExCodecs ships binaries
for: macOS (Apple Silicon and Intel), Linux (x86_64 and aarch64, glibc and
musl) and Windows (x86_64). Check at runtime with:

```elixir
ExZarr.Codecs.available_codecs()
# => [:none, :zlib, :crc32c, :zstd, :lz4, :snappy, :blosc, :bzip2]
```

If only `:none` and `:zlib` are listed, the ExCodecs NIF did not load,
usually because the precompiled download failed during `mix deps.compile`.
Re-fetch with network access:

```bash
mix deps.clean ex_codecs --build
mix deps.get && mix deps.compile ex_codecs
```

### Building ExCodecs from source

On a platform without a precompiled binary, build the NIF from source. This
needs a Rust toolchain:

```elixir
# mix.exs
{:rustler, ">= 0.0.0", optional: true}

# config/config.exs
config :rustler_precompiled, :force_build, ex_codecs: true
```

## Telemetry

Range reads emit `[:ex_zarr, :shard, :range_read]` events; see the
[telemetry guide](guides/telemetry.md).

## See Also

- [Compression and Codecs](guides/compression_codecs.md)
- [Installation](guides/installation.md)
