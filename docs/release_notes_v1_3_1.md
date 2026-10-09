# v1.3.1 Release Notes

ExZarr v1.3.1 is a patch release. It fixes performance and correctness issues
found reviewing v1.3.0, and makes every shipped livebook run. Upgrading from
1.3.0 needs no code changes.

```elixir
{:ex_zarr, "~> 1.3"}
```

## Nx

- `ExZarr.Nx.stream_chunk_tensors/2` crops padded edge chunks one contiguous
  row at a time. A 999x1000 float32 edge chunk took about 300 ms in 1.3.0 and
  now takes under 1 ms.
- An array whose dtype has no Nx type yields a single `{:error, reason}` from
  `stream_chunk_tensors/2` instead of one error per chunk.
- `ExZarr.Nx.DataLoader.shuffled_batch_stream/3` and
  `paired_shuffled_batch_stream/4` group the shuffled indices in one pass. In
  1.3.0 the index slicing alone grew with the square of the sample count.
- Shuffling no longer changes the calling process's `:rand` state. The same
  `:seed` still gives the same order as in 1.3.0.
- `to_tensor_chunked/3` applies `:names`, as `to_tensor/2` does.

## Livebooks

- `01_04_codecs_and_pipelines` ran into `:gzip` with a Zarr v2 array and
  `compressor: nil`; it now uses `:zlib` and `:none`. `:gzip` is a Zarr v3
  codec.
- `03_03_training_from_zarr` trains on an independent second feature from
  zero-initialized weights with Adam, so it reliably reaches the line
  (`weights` about `[2.0, 0.0]`, `bias` about `1.0`) and prints the same numbers
  on every run. It uses Axon 0.8's `Axon.ModelState`.
- `mix livebook.test` runs cells one at a time, as Livebook does, and
  `--local` tests notebooks against the checkout. CI now runs every shipped
  livebook.

## Documentation

- The guides no longer say `:gzip` always works; it applies to Zarr v3 arrays.
- The Nx guide's speed figures are measured: for an 8 MB float64 array in
  memory storage on an Apple M1 Max, `to_tensor/2` takes about 75 ms
  uncompressed and 117 ms with the default zlib.
- The v1.3.0 notes and roadmap record that Explorer streaming, planned for
  1.3, was dropped. Columnar data and Explorer belong in
  [ex_arrow](https://hex.pm/packages/ex_arrow).

Full list: [CHANGELOG](https://github.com/AnimaLogica/ExZarr/blob/main/CHANGELOG.md).
