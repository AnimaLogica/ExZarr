# ExZarr Livebook Gallery

**Executable tutorials for cloud-native, concurrent array data in Elixir**

This gallery is a curated collection of **Elixir Livebooks** demonstrating how to use
**ExZarr** — a Zarr v2/v3 array storage library — for AI / GenAI, finance, and
scientific workloads.

These notebooks appear under **Examples** and **Cookbooks** in `mix docs`.

## How to run

From the repository root:

```bash
mix deps.get
mix compile
mix livebook.server
```

Or open any `.livemd` in [Livebook](https://livebook.dev/). Path installs use
`Path.join(__DIR__, "../..")` from nested folders.

## Examples (tutorials)

| Livebook | Topic |
|----------|--------|
| [`01_core_zarr/01_01_first_zarr_array.livemd`](01_core_zarr/01_01_first_zarr_array.livemd) | Create → write → read → stream → save |
| [`01_core_zarr/01_03_chunk_streaming.livemd`](01_core_zarr/01_03_chunk_streaming.livemd) | Sequential vs parallel chunk streaming |
| [`01_core_zarr/01_04_codecs_and_pipelines.livemd`](01_core_zarr/01_04_codecs_and_pipelines.livemd) | Codecs and pipelines |
| [`04_ai_genai/04_01_embeddings_in_zarr.livemd`](04_ai_genai/04_01_embeddings_in_zarr.livemd) | Embeddings in Zarr |
| [`05_finance/05_01_tick_data_cube.livemd`](05_finance/05_01_tick_data_cube.livemd) | Tick data cube |
| [`broadway_pipeline.livemd`](broadway_pipeline.livemd) | Broadway chunk pipeline |
| [`nx_streaming.livemd`](nx_streaming.livemd) | Nx + streaming |
| [`zarr_fundamentals.livemd`](zarr_fundamentals.livemd) | Chunked arrays deep dive |
| [`earthmover_datacube.livemd`](earthmover_datacube.livemd) | Datacubes & chunk computation |
| [`xarray_zarr_intro.livemd`](xarray_zarr_intro.livemd) | Groups, attributes, Xarray-style layout |
| [`benchmarking_zarr.livemd`](benchmarking_zarr.livemd) | Access-pattern benchmarks |

Script counterparts: [`examples/README.md`](../examples/README.md).

> Prefer these `livebooks/` paths. Copies under `notebooks/` are legacy duplicates.

## Cookbooks (production patterns)

| Livebook | Topic |
|----------|--------|
| [`06_cookbook/06_01_100gb_arrays.livemd`](06_cookbook/06_01_100gb_arrays.livemd) | Large-array streaming |
| [`06_cookbook/06_02_1tb_arrays.livemd`](06_cookbook/06_02_1tb_arrays.livemd) | Flow / multi-stage |
| [`06_cookbook/06_03_image_archives.livemd`](06_cookbook/06_03_image_archives.livemd) | Image tiles |
| [`06_cookbook/06_04_ml_pipelines.livemd`](06_cookbook/06_04_ml_pipelines.livemd) | ML batching |
| [`06_cookbook/06_05_geospatial.livemd`](06_cookbook/06_05_geospatial.livemd) | Time/lat/lon slices |
| [`06_cookbook/06_06_scientific_computing.livemd`](06_cookbook/06_06_scientific_computing.livemd) | Map-reduce |
| [`06_cookbook/06_07_distributed.livemd`](06_cookbook/06_07_distributed.livemd) | Multi-node (experimental) |
