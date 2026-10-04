# v1.2.0 Release Notes

## Zarr 3.1 Interoperability & Range-Aware Cloud I/O

ExZarr v1.2.0 focuses on Zarr 3.1 conformance, standard `sharding_indexed`
interoperability, optional byte-range cloud I/O, migrating Azure Blob
storage to `azure_sdk`, and moving the compression codecs to
[ExCodecs](https://hex.pm/packages/ex_codecs): precompiled pure-Rust NIFs, so
ExZarr itself has no native code and needs no Zig, compiler or system
libraries.

## Highlights

### Zarr 3.1 metadata

- Scalar arrays (`shape: {}`) and zero-length dimensions
- Spec-aligned dimension names (arbitrary strings / null)
- Extension definitions with `must_understand`
- `storage_transformers` preserved in metadata (execution deferred)

### Standard sharding + range reads

- `sharding_indexed` v1.0 dense uint64 index with empty sentinel, readable and
  writable by zarr-python
- Optional `chunk_info` / `read_chunk_range` backend capabilities
- Range-aware inner-chunk reads with full-shard fallback
- S3, GCS, Azure, filesystem, and memory backends

### Codecs via ExCodecs

- zstd, lz4, snappy, blosc, bzip2 and crc32c come from ExCodecs `~> 0.2.4`,
  precompiled for macOS, Linux (glibc and musl) and Windows. zlib/gzip use
  Erlang's `:zlib`.
- Byte formats match numcodecs, so zarr-python reads ExZarr's lz4, bzip2 and
  blosc data (v2 and v3), and ExZarr reads zarr-python's.
- New `compressor_config:` option, for example:

  ```elixir
  ExZarr.create(
    shape: {1000, 1000},
    chunks: {100, 100},
    compressor: :blosc,
    compressor_config: [cname: :zstd, level: 5, shuffle: :bit, typesize: 8]
  )
  ```

  v2 arrays keep the settings in `.zarray` (numcodecs form); v3 arrays keep
  them in the codec configuration.
- `config :ex_zarr, default_zarr_version: 3` now applies to new arrays
  (unset: v2, as before).
- Decompressed chunks are capped at 256 MiB by default
  (`config :ex_zarr, max_chunk_bytes: ...`).

### AzureSDK migration

```elixir
# Shared Key
ExZarr.open(
  storage: :azure_blob,
  account_name: "...",
  account_key: "...",
  container: "...",
  prefix: "..."
)

# Advanced: inject AzureSDK.Storage.Client
ExZarr.open(
  storage: :azure_blob,
  azure_client: client,
  container: "...",
  zarr_format: 3
)
```

`azurex` is removed.

### Python interoperability matrix

Fixture generator under `test/support/python_fixtures/` and a blocking CI job
covering zarr-python 2.18.3 / 3.2.1 / 3.3.0 / 3.4.0, in both directions.

### Security

- Optional HTTP client is `req ~> 0.6.1` (CVE-2026-49755)
- Unused `google_api_storage` removed; GCS uses Goth + Req

## Upgrade

- **OTP 26 or later** is required (ExCodecs NIFs target NIF 2.17).
- Remove any Zig, `COMPRESSION_LIB_DIRS`, `EX_ZARR_BUILD` or system
  compression-library setup; it is no longer used.
- Azure users: add `{:azure_sdk, "~> 0.4.1", optional: true}` and remove `azurex`.
- GCS/Azure users: use `{:req, "~> 0.6.1"}`.
- Arrays written with ExZarr's pre-1.2 private shard index must be rewritten.
- Cloud v3 arrays now use `zarr.json` and `c/...` keys.
- New lz4 and bzip2 data uses the numcodecs formats. ExZarr 1.2 still reads
  data written by 1.1, but ExZarr 1.1 cannot read lz4/bzip2 data written by 1.2.
- `ExZarr.create/1` now returns an error for unknown compressors, invalid
  `compressor_config` and Zarr versions other than 2 or 3, and for v3
  compressors without a v3 codec (such as `:snappy`), which were previously
  stored uncompressed.

## Known limitations

- No storage-transformer execution
- No adaptive range coalescing
- No partial writes inside cloud shards

See [CHANGELOG.md](https://github.com/AnimaLogica/ExZarr/blob/main/CHANGELOG.md#120---2026-10-04) and [ROADMAP.md](https://github.com/AnimaLogica/ExZarr/blob/main/docs/ROADMAP.md).
