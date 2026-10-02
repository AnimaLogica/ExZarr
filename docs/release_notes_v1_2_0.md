# ExZarr v1.2.0 Release Notes

## Zarr 3.1 Interoperability & Range-Aware Cloud I/O

ExZarr v1.2.0 focuses on Zarr 3.1 conformance, standard `sharding_indexed`
interoperability, optional byte-range cloud I/O, migrating Azure Blob
storage to `azure_sdk`, and shipping **precompiled Zig codec NIFs** for
Hex/Livebook installs (see `PRECOMPILATION.md`).

## Highlights

### Zarr 3.1 metadata

- Scalar arrays (`shape: {}`) and zero-length dimensions
- Spec-aligned dimension names (arbitrary strings / null)
- Extension definitions with `must_understand`
- `storage_transformers` preserved in metadata (execution deferred)

### Standard sharding + range reads

- `sharding_indexed` v1.0 dense uint64 index with empty sentinel
- Optional `chunk_info` / `read_chunk_range` backend capabilities
- Range-aware inner-chunk reads with full-shard fallback
- S3, GCS, Azure, filesystem, and memory backends

### Precompiled Zig codec NIFs

- Hex/Livebook installs download platform NIFs (no Zig toolchain required)
- Source builds via `EX_ZARR_BUILD=1` or missing checksum file
- CI workflow: `.github/workflows/precompile.yml`

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

Fixture generator under `test/support/python_fixtures/` and a CI job covering
zarr-python 2.x / 3.2 / 3.3 / 3.4.

### Security

- Optional HTTP client is `req ~> 0.6.1` (CVE-2026-49755)
- Unused `google_api_storage` removed; GCS uses Goth + Req

## Upgrade

- Azure users: add `{:azure_sdk, "~> 0.4.1", optional: true}` and remove `azurex`
- Arrays written with ExZarr’s pre-1.2 private shard index must be rewritten
- Cloud v3 arrays now use `zarr.json` and `c/...` keys
- GCS/Azure users: use `{:req, "~> 0.6.1"}` (ExZarr overrides older azure_sdk caps)

## Known limitations

- No storage-transformer execution
- No adaptive range coalescing
- No partial writes inside cloud shards

See [CHANGELOG.md](../CHANGELOG.md) and [ROADMAP.md](ROADMAP.md).
