# Range-Aware Sharded Read Showcase

Demonstrates ExZarr 1.2.0 reading a sharded v3 array and computing an Nx mean
over a small region.

```elixir
Mix.install([
  {:ex_zarr, path: Path.expand("..", __DIR__)},
  {:nx, "~> 0.7"}
])

alias ExZarr.Array

path = Path.join(System.tmp_dir!(), "ex_zarr_showcase_#{System.unique_integer([:positive])}")
File.rm_rf!(path)

{:ok, array} =
  ExZarr.create(
    shape: {32, 32},
    chunks: {8, 8},
    dtype: :float32,
    zarr_version: 3,
    storage: :filesystem,
    path: path,
    codecs: [
      %{
        name: "sharding_indexed",
        configuration: %{
          chunk_shape: [2, 2],
          codecs: [%{name: "bytes"}],
          index_codecs: [%{name: "bytes"}],
          index_location: "end"
        }
      }
    ]
  )

row = for i <- 0..31, into: <<>>, do: <<i * 1.0::float-little-32>>

for r <- 0..31 do
  :ok = Array.set_slice(array, row, start: {r, 0}, stop: {r + 1, 32})
end

{:ok, array} = ExZarr.open(path: path)
{:ok, binary} = Array.get_slice(array, start: {0, 0}, stop: {8, 8})
tensor = Nx.from_binary(binary, {:f, 32}) |> Nx.reshape({8, 8})

IO.inspect(%{
  region: {{0, 0}, {8, 8}},
  mean: Nx.to_number(Nx.mean(tensor)),
  logical_bytes: 8 * 8 * 4,
  note: "On S3/GCS/Azure, range-capable backends fetch shard index + inner chunk ranges only"
})
```
