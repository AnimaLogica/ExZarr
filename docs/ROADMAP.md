# ExZarr Roadmap

## v1.2.0 (Current) — Zarr 3.1 Interoperability & Range-Aware Cloud I/O

- [x] Zarr 3.1 metadata: scalars, zero-length dims, dimension names, extensions, `storage_transformers`
- [x] Spec-correct `sharding_indexed` v1.0
- [x] Optional byte-range storage (`chunk_info` / `read_chunk_range`)
- [x] Range-aware sharded reads with full-shard fallback
- [x] Version-aware cloud object keys (S3 / GCS / Azure)
- [x] Azure Blob backend on `azure_sdk ~> 0.4.1` (azurex removed)
- [x] Python fixture generator + CI matrix job for zarr 2.x / 3.2 / 3.3 / 3.4

---

## v1.1.0 — BEAM-Native Streaming

Released 2026-06-12. Backward compatible with v1.0.

- [x] `stream_chunks/2`, `stream_slices/3`, `write_stream/3`
- [x] Telemetry, Flow / GenStage / Broadway integrations
- [x] Cookbook and streaming livebooks

---

## v1.3.0 (Planned) — Data Science Interop

- [ ] Explorer direct streaming integration
- [ ] `ExZarr.Nx` streaming recipes
- [ ] Livebook curriculum completion

---

## v1.4.0 (Planned) — Performance & Packaging

- [ ] Async codec pipeline
- [ ] Vendored/static codec libraries
- [ ] Adaptive range coalescing
- [ ] Storage-transformer execution (beyond metadata)

---

## v2.0.0 (Future) — Distributed Processing

- [ ] Multi-node chunk processing
- [ ] Cross-node telemetry

---

## Deferred from v1.2 (explicit)

- Unified retry layer across cloud SDKs
- Native multi-range / coalescing heuristics
- Partial writes inside cloud shards
- Explorer / new Nx APIs
