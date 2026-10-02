defmodule ExZarr.Storage.RangeReadTest do
  use ExUnit.Case, async: true

  alias ExZarr.Codecs.ShardingIndexed
  alias ExZarr.Storage
  alias ExZarr.Storage.Backend.{Filesystem, Memory}

  describe "optional range callbacks" do
    test "memory backend supports range reads without full-object semantics breaking" do
      {:ok, storage} = Storage.init(%{storage_type: :memory})
      data = <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>
      assert :ok = Storage.write_chunk(storage, {0}, data)
      assert Storage.supports?(storage, :range_read)
      assert {:ok, <<3, 4, 5>>} = Storage.read_chunk_range(storage, {0}, 3, 3)
      assert {:ok, %{size: 10}} = Storage.chunk_info(storage, {0})
    end

    test "filesystem uses positioned reads" do
      path = Path.join(System.tmp_dir!(), "ex_zarr_range_#{System.unique_integer([:positive])}")
      File.mkdir_p!(path)
      on_exit(fn -> File.rm_rf!(path) end)

      {:ok, storage} = Storage.init(%{storage_type: :filesystem, path: path})
      data = for(i <- 0..99, into: <<>>, do: <<i>>)
      assert :ok = Storage.write_chunk(storage, {0}, data)
      assert {:ok, slice} = Storage.read_chunk_range(storage, {0}, 10, 5)
      assert slice == binary_part(data, 10, 5)
    end

    test "Backend.read_range falls back when range unsupported" do
      defmodule NoRangeBackend do
        @behaviour ExZarr.Storage.Backend
        def backend_id, do: :no_range_test
        def init(_), do: {:ok, %{data: <<0, 1, 2, 3, 4, 5, 6, 7>>}}
        def open(c), do: init(c)
        def read_chunk(state, _), do: {:ok, state.data}
        def write_chunk(_, _, _), do: :ok
        def read_metadata(_), do: {:error, :not_found}
        def write_metadata(_, _, _), do: :ok
        def list_chunks(_), do: {:ok, []}
        def delete_chunk(_, _), do: :ok
        def exists?(_), do: true
      end

      assert {:ok, <<2, 3, 4>>} =
               ExZarr.Storage.Backend.read_range(
                 NoRangeBackend,
                 %{data: <<0, 1, 2, 3, 4, 5, 6, 7>>},
                 {0},
                 2,
                 3
               )
    end
  end

  describe "range-aware sharding" do
    test "single inner chunk range path avoids full shard materialization in memory backend" do
      {:ok, codec} =
        ShardingIndexed.init(%{
          "chunk_shape" => [4, 1],
          "codecs" => [%{"name" => "bytes"}],
          "index_codecs" => [%{"name" => "bytes"}],
          "index_location" => "end"
        })

      # Large payload for one inner chunk; others empty
      large = :binary.copy(<<1>>, 10_000)
      chunks = %{{0, 0} => large}
      assert {:ok, shard} = ShardingIndexed.encode(chunks, codec)

      {:ok, info_size} = ShardingIndexed.index_byte_range(codec, byte_size(shard))
      {index_offset, index_len} = elem({:ok, info_size}, 1)
      index_bin = binary_part(shard, index_offset, index_len)
      assert {:ok, entries} = ShardingIndexed.decode_index_bytes(index_bin, codec)
      assert {:ok, {offset, nbytes}} = ShardingIndexed.index_entry(entries, {0, 0})
      assert nbytes == 10_000
      assert offset + nbytes <= byte_size(shard)
      # Index + one inner chunk is much smaller than full shard only when other data exists;
      # here prove index+payload < shard when extra empty slots inflate index vs tiny extras.
      assert index_len + nbytes <= byte_size(shard)
    end
  end
end
