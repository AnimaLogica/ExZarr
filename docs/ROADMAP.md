# Roadmap

## v1.2.0 - Zarr 3.1 Interoperability & Range-Aware Cloud I/O

Released 2026-10-04. Backward compatible with v1.1 (rewrite pre-1.2 private shards; OTP 26+).

- [x] Zarr 3.1 metadata: scalars, zero-length dims, dimension names, extensions, `storage_transformers`
- [x] Spec-correct `sharding_indexed` v1.0
- [x] Optional byte-range storage (`chunk_info` / `read_chunk_range`)
- [x] Range-aware sharded reads with full-shard fallback
- [x] Version-aware cloud object keys (S3 / GCS / Azure)
- [x] Azure Blob backend on `azure_sdk ~> 0.4.1` (azurex removed)
- [x] Codecs via ExCodecs (precompiled pure-Rust NIFs; no Zig or system libraries)
- [x] `compressor_config:` and `default_zarr_version` applied
- [x] Python fixture generator + CI matrix job for zarr 2.x / 3.2 / 3.3 / 3.4

---

## v1.1.0 - BEAM-Native Streaming

Released 2026-06-12. Backward compatible with v1.0.

- [x] `stream_chunks/2`, `stream_slices/3`, `write_stream/3`
- [x] Telemetry, Flow / GenStage / Broadway integrations
- [x] Cookbook and streaming livebooks

---

## v1.3.0 - Data Science Interop

Released 2026-10-08.

- [x] `ExZarr.Nx.stream_chunk_tensors/2` (stored chunks → tensors, edge crops)
- [x] DataLoader documented against its real shuffle (full index list)
- [x] Livebook MVP: metadata, Zarr↔Nx, minibatches, Axon toy train
- [ ] ~~Explorer direct streaming~~ Dropped from 1.3: columnar data and Explorer belong in [ex_arrow](https://hex.pm/packages/ex_arrow), and Binsparse in [ex_graphblas](https://hex.pm/packages/ex_graphblas)

---

## v1.4.0 (Planned) - Performance & Packaging

- [ ] Async codec pipeline
- [ ] Vendored/static codec libraries
- [ ] Adaptive range coalescing
- [ ] Storage-transformer execution (beyond metadata)

---

## v2.0.0 (Future) - Distributed Processing

- [ ] Multi-node chunk processing
- [ ] Cross-node telemetry

---

## Deferred (explicit)

- Unified retry layer across cloud SDKs
- Native multi-range / coalescing heuristics
- Partial writes inside cloud shards
- Partial shuffle buffer (`:shuffle_buffer_size` is accepted and ignored)
- Contiguous `load_samples_at_indices/3` reads
