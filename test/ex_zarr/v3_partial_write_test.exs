defmodule ExZarr.V3PartialWriteTest do
  use ExUnit.Case, async: true

  alias ExZarr.Array

  setup do
    path = Path.join(System.tmp_dir!(), "ex_zarr_rmw_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, path: path}
  end

  defp ints(list), do: for(i <- list, into: <<>>, do: <<i::signed-little-32>>)

  # A partial write must decode the stored chunk with the array's v3 codec
  # pipeline. Reopened v3 arrays have no v2 compressor, so decoding with it
  # used to splice new values into the raw zstd frame.
  test "partial write into a reopened v3 array keeps the other values", %{path: path} do
    {:ok, array} =
      ExZarr.create(
        shape: {4},
        chunks: {4},
        dtype: :int32,
        zarr_version: 3,
        storage: :filesystem,
        path: path
      )

    :ok = Array.set_slice(array, ints([1, 2, 3, 4]), start: {0}, stop: {4})

    {:ok, reopened} = ExZarr.open(path: path)
    :ok = Array.set_slice(reopened, ints([99]), start: {1}, stop: {2})

    {:ok, again} = ExZarr.open(path: path)
    assert {:ok, data} = Array.get_slice(again, start: {0}, stop: {4})
    assert data == ints([1, 99, 3, 4])
  end

  test "row-by-row writes into a sharded array", %{path: path} do
    {:ok, array} =
      ExZarr.create(
        shape: {8, 8},
        chunks: {4, 4},
        shard_shape: {2, 2},
        dtype: :int32,
        zarr_version: 3,
        storage: :filesystem,
        path: path
      )

    for r <- 0..7 do
      :ok =
        Array.set_slice(array, ints(Enum.map(0..7, &(r * 8 + &1))),
          start: {r, 0},
          stop: {r + 1, 8}
        )
    end

    {:ok, reopened} = ExZarr.open(path: path)
    :ok = Array.set_slice(reopened, ints([-1]), start: {5, 5}, stop: {6, 6})

    expected = ints(Enum.map(0..63, fn i -> if i == 45, do: -1, else: i end))
    {:ok, again} = ExZarr.open(path: path)
    assert {:ok, ^expected} = Array.get_slice(again, start: {0, 0}, stop: {8, 8})
  end
end
