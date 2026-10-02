# Range-aware sharded read showcase.
#
# Writes a sharded Zarr v3 array, then reads one small region. Only the shard
# index and the inner chunks covering the region are fetched; telemetry
# reports the bytes actually read. The region is summarised with Nx.
#
# Run from the repository root:
#
#     mix run examples/range_aware_sharded_nx.exs

alias ExZarr.Array

defmodule Showcase.RangeReadLogger do
  def handle_event(_event, measurements, metadata, _config) do
    IO.inspect(Map.merge(measurements, metadata), label: "shard read")
  end
end

path = Path.join(System.tmp_dir!(), "ex_zarr_showcase_#{System.unique_integer([:positive])}")

# 32x32 float32 array. Each shard is 16x16 elements holding 4x4 inner chunks
# of 4x4 elements (spec metadata: chunk_grid 16x16, sharding chunk_shape 4x4).
{:ok, array} =
  ExZarr.create(
    shape: {32, 32},
    chunks: {4, 4},
    shard_shape: {4, 4},
    dtype: :float32,
    zarr_version: 3,
    storage: :filesystem,
    path: path
  )

data = for i <- 0..(32 * 32 - 1), into: <<>>, do: <<i * 1.0::float-little-32>>
:ok = Array.set_slice(array, data, start: {0, 0}, stop: {32, 32})

:telemetry.attach(
  "showcase-range-reads",
  [:ex_zarr, :shard, :range_read],
  &Showcase.RangeReadLogger.handle_event/4,
  nil
)

{:ok, array} = ExZarr.open(path: path)
{:ok, binary} = Array.get_slice(array, start: {0, 0}, stop: {4, 4})
tensor = binary |> Nx.from_binary(:f32) |> Nx.reshape({4, 4})

IO.inspect(
  %{
    region: {{0, 0}, {4, 4}},
    mean: Nx.to_number(Nx.mean(tensor)),
    shard_bytes_on_disk: File.stat!(Path.join([path, "c", "0", "0"])).size
  },
  label: "result"
)

:telemetry.detach("showcase-range-reads")
File.rm_rf!(path)
