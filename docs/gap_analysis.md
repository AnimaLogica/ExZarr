# Gap Analysis

As of v1.2.0

## Comparison Matrix

| Capability | Python Zarr | TensorStore | TileDB | ExZarr v1.1 | ExZarr v1.2 |
|------------|-------------|-------------|--------|-------------|-------------|
| Lazy chunk iteration | Yes | Yes | Yes | Yes (`stream_chunks`) | Yes |
| Parallel reads | Thread pool | Async I/O | Thread pool | Task + Flow + GenStage | Same + range-aware shard reads |
| Write streaming | Yes | Yes | Yes | Yes (`write_stream`) | Yes |
| Backpressure | Limited | Yes | Yes | GenStage + Flow | Same |
| Fault-tolerant pipelines | External (Dask) | Limited | Yes | Broadway | Same |
| Cloud storage | fsspec | Native GCS/S3 | S3 | S3/GCS/Azure | AzureSDK; version-aware keys; optional byte ranges |
| Spec sharding | Yes | Yes | Yes | Private / partial | Spec `sharding_indexed` v1.0 + zarr-python CI |
| Nx/torch integration | Via Dask/Xarray | TF/JAX | Limited | Streaming tensors | Same (Explorer planned v1.3) |
| Distributed processing | Dask | Limited | Yes | Stretch goal | Deferred to v2.0 |
| Telemetry | Limited | Yes | Yes | Implemented | + shard `range_read` events |

## BEAM Unique Advantages

1. **Process isolation:** Each chunk read runs in an isolated process. A failing
   chunk decode does not crash the entire pipeline when `:on_error` is configured.

2. **Preemptive scheduling:** CPU-bound decompression scales across cores without
   a GIL, unlike Python threading.

3. **Supervision:** Broadway pipelines restart failed stages without losing the
   entire array processing job.

4. **Cheap concurrency:** Spawning 100+ concurrent chunk reads is practical on the
   BEAM where OS thread pools would be expensive.

5. **Hot code upgrades:** Long-running streaming pipelines can be upgraded in
   place on production nodes.

## Remaining Gaps (Post v1.2.0)

- Storage-transformer runtime execution
- Adaptive multi-range coalescing / partial writes inside cloud shards
- Explorer direct streaming integration (planned v1.3)
- Async codec pipeline (overlap I/O and decode) (planned v1.4)
- Multi-node distributed chunk processing (planned v2.0)

## Opportunities

- Elixir/Phoenix data pipelines that need Zarr streaming without leaving the BEAM
- Livebook-first education for scientific Elixir community
- Cloud-native deployments on Fly.io/Gigalixir with Broadway pipelines
