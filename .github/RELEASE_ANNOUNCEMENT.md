# ExZarr v1.2.0 - Zarr 3.1 Interoperability & Range-Aware Cloud I/O

We're pleased to announce **ExZarr v1.2.0**: Zarr 3.1 conformance, standard
`sharding_indexed` interoperability with zarr-python, optional byte-range cloud
I/O, AzureSDK migration, and **precompiled Zig codec NIFs** for Hex/Livebook.

## Highlights

### Zarr 3.1 metadata

- Scalar arrays (`shape: {}`) and zero-length dimensions
- Spec-aligned dimension names (arbitrary strings / null)
- Extension definitions with `must_understand`
- `storage_transformers` preserved in metadata (execution deferred)

### Standard sharding + range reads

- Spec-correct `sharding_indexed` v1.0 (dense uint64 index, empty sentinel)
- Optional `chunk_info` / `read_chunk_range` backend capabilities
- Range-aware inner-chunk reads with full-shard fallback
- S3, GCS, Azure, filesystem, and memory backends

### Precompiled Zig codec NIFs

- Hex/Livebook installs download platform NIFs (no Zig toolchain required)
- Source builds via `EX_ZARR_BUILD=1` or when checksums are missing
- See [docs/PRECOMPILATION.md](../docs/PRECOMPILATION.md)

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

- Azure users: add `azure_sdk`, remove `azurex`
- Rewrite arrays written with ExZarr’s pre-1.2 private shard index
- Cloud v3 arrays use `zarr.json` and `c/...` keys
- GCS/Azure HTTP client: `{:req, "~> 0.6.1"}` (CVE-2026-49755)

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

See [CHANGELOG.md](../CHANGELOG.md#120---2026-10-03).
