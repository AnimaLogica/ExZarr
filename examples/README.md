# Examples (`mix run`)

Runnable scripts under `examples/`. From the repo root:

```bash
mix deps.get
mix run examples/basic_usage.exs
```

| Script | Description |
|--------|-------------|
| `basic_usage.exs` | Create, write, read a small array |
| `climate_data.exs` | Climate-style multidimensional workflow |
| `custom_codec_example.exs` | Register and use a custom codec |
| `dimension_names.exs` | Named dimensions |
| `nx_integration.exs` | ExZarr ↔ Nx tensors |
| `nx_optimized_conversion.exs` | Faster tensor conversion patterns |
| `nx_data_loader.exs` / `nx_data_loader_demo.exs` | Batch DataLoader usage |
| `python_interop_demo.exs` | Round-trip with Python zarr |
| `range_aware_sharded_nx.exs` | Range reads on sharded arrays |
| `s3_storage.exs` | S3 backend demo |
| `sharded_cloud_storage.exs` | Sharding + cloud layout |

For interactive tutorials, see the [Livebook gallery](../docs/livebooks/README.md).
