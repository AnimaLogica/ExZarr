# ExZarr v1.2.0 - Zarr 3.1 Interoperability & Range-Aware Cloud I/O

We're pleased to announce **ExZarr v1.2.0**: Zarr 3.1 conformance, standard
`sharding_indexed` interoperability with zarr-python, optional byte-range cloud
I/O, AzureSDK migration, and compression codecs from
[ExCodecs](https://hex.pm/packages/ex_codecs): precompiled pure-Rust NIFs, so
ExZarr has no native code and needs no Zig, compiler or system libraries.

## Highlights

### Zarr 3.1 metadata

- Scalar arrays (`shape: {}`) and zero-length dimensions
- Spec-aligned dimension names (arbitrary strings / null)
- Extension definitions with `must_understand`
- `storage_transformers` preserved in metadata (execution deferred)

### Standard sharding + range reads

- Spec-correct `sharding_indexed` v1.0 (dense uint64 index, empty sentinel),
  readable and writable by zarr-python
- Optional `chunk_info` / `read_chunk_range` backend capabilities
- Range-aware inner-chunk reads with full-shard fallback
- S3, GCS, Azure, filesystem, and memory backends

### Codecs via ExCodecs

- zstd, lz4, snappy, blosc, bzip2 and crc32c from ExCodecs, precompiled for
  macOS, Linux (glibc and musl) and Windows; zlib/gzip via Erlang `:zlib`
- numcodecs-compatible byte formats: zarr-python reads ExZarr's lz4, bzip2
  and blosc data, and ExZarr reads zarr-python's
- New `compressor_config:` option (e.g. `[level: 9]`, or Blosc `cname`,
  `shuffle`, `typesize`), stored in `.zarray` / `zarr.json`
- `config :ex_zarr, default_zarr_version: 3` now applies to new arrays

### AzureSDK migration

```elixir
ExZarr.open(
  storage: :azure_blob,
  account_name: "...",
  account_key: "...",
  container: "...",
  prefix: "..."
)
```

`azurex` is removed. Prefer `{:azure_sdk, "~> 0.4.1", optional: true}`.

### Python interoperability matrix

CI covers zarr-python **2.18.3 / 3.2.1 / 3.3.0 / 3.4.0** with a fixture
generator under `test/support/python_fixtures/`. Local steps:
[Testing Python Interoperability](../docs/INTEROPERABILITY.md#testing-python-interoperability).

## Installation

```elixir
def deps do
  [
    {:ex_zarr, "~> 1.2"}
  ]
end
```

## Upgrade notes

- OTP 26 or later is required
- Drop any Zig / system compression-library setup; it is no longer used
- Azure users: add `azure_sdk`, remove `azurex`
- Rewrite arrays written with ExZarr’s pre-1.2 private shard index
- Cloud v3 arrays use `zarr.json` and `c/...` keys
- GCS/Azure HTTP client: `{:req, "~> 0.6.1"}` (CVE-2026-49755)
- New lz4/bzip2 data uses the numcodecs formats; 1.2 reads 1.1 data, but 1.1
  cannot read lz4/bzip2 data written by 1.2
- `ExZarr.create/1` returns errors for unknown compressors, invalid
  `compressor_config` and unsupported Zarr versions

## Known limitations

- No storage-transformer execution
- No adaptive range coalescing
- No partial writes inside cloud shards

## Get Started

- 📖 [Documentation](https://hexdocs.pm/ex_zarr)
- 🚀 [Quick Start](https://github.com/AnimaLogica/ExZarr#quick-start)
- 📝 [Release notes](../docs/release_notes_v1_2_0.md)
- 🗺️ [Roadmap](../docs/ROADMAP.md)
- 💬 [Issues](https://github.com/AnimaLogica/ExZarr/issues)

## Full changelog

See [CHANGELOG.md](../CHANGELOG.md#120---2026-10-04).
