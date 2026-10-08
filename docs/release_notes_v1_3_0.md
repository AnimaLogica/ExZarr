# v1.3.0 Release Notes

## Data Science Interop

ExZarr v1.3.0 adds Nx recipes for stored chunks and sample batches, plus a
small livebook set you can run from the repo.

ExZarr remains a dense chunked array and group store. Columnar batches belong
in [ex_arrow](https://hex.pm/packages/ex_arrow). Binsparse groups belong in
[ex_graphblas](https://hex.pm/packages/ex_graphblas).

### Scope change

Explorer direct streaming was planned for 1.3 and is not included. Explorer
works on columnar data, which is ex_arrow's job, so it will not be added to
ExZarr.

## Highlights

### Chunk tensors

`ExZarr.Nx.stream_chunk_tensors/2` wraps `Array.stream_chunks/2`. Each binary
becomes an `Nx.Tensor` using the array dtype. When a chunk is stored at the
full chunk size and the array ends inside it, the tensor is the in-bounds
region.

```elixir
array
|> ExZarr.Nx.stream_chunk_tensors(concurrency: 4)
|> Enum.map(fn {:ok, tensor} -> Nx.sum(tensor) end)
```

`:concurrency`, `:ordered`, `:timeout`, `:on_error`, `:filter`, and
`:include_missing` are the streaming options. `:backend` and `:names` apply to the tensors.

### Batches

`ExZarr.Nx.DataLoader.batch_stream/3` and `paired_batch_stream/4` slice along
the first axis with `get_slice/2`. A batch can cross chunk boundaries.

`shuffled_batch_stream/3` shuffles every sample index for the epoch.
`:shuffle_buffer_size` is accepted and ignored. Pass `:seed` for a repeatable
order.

### Livebooks

- `docs/livebooks/01_core_zarr/01_02_metadata_and_chunks.livemd`
- `docs/livebooks/03_nx_ml/03_01_zarr_to_nx.livemd`
- `docs/livebooks/03_nx_ml/03_02_streaming_minibatches.livemd`
- `docs/livebooks/03_nx_ml/03_03_training_from_zarr.livemd`
- `docs/livebooks/nx_streaming.livemd`

```elixir
{:ex_zarr, "~> 1.3"}
```

Hex owner remains `thanos`. Source: https://github.com/AnimaLogica/ExZarr
