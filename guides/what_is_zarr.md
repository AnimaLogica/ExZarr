# What is Zarr?

Zarr is a format for storing **chunked, compressed, N-dimensional arrays**. It is designed for large scientific and ML datasets that do not fit in memory, and for efficient parallel access on local disks and cloud object stores.

## Why chunks?

An array is divided into fixed-size **chunks**. Each chunk can be:

- Compressed independently
- Read or written without loading the whole array
- Fetched in parallel over the network

That makes Zarr a natural fit for cloud-native workflows and for the BEAM’s concurrent I/O model.

## What is ExZarr?

ExZarr is a **pure Elixir** implementation of the Zarr v2 and v3 specifications. It is not a Python wrapper: it speaks the same on-disk and cloud layout as zarr-python and other Zarr implementations, so data can be shared across languages.

**Typical uses:**

- Scientific and numerical pipelines with persistent array storage
- Machine learning datasets and embedding stores
- Cloud backends (S3, GCS, Azure Blob)
- Concurrent ingestion and streaming over chunks

## Next steps

- [Introduction](introduction.md) — create, write, and read an array in a few minutes
- [Core Concepts](core_concepts.md) — arrays, chunks, codecs, and metadata
- [Livebook Gallery](../livebooks/README.md) — runnable Examples and Cookbooks
