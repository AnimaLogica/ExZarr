defmodule ExZarr.ShardingRobustnessTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

  alias ExZarr.Array
  alias ExZarr.Codecs.ShardingIndexed
  alias ExZarr.Storage

  defp sharded_array(opts \\ []) do
    ExZarr.create(
      Keyword.merge(
        [
          shape: {8, 8},
          chunks: {2, 2},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3,
          storage: :memory
        ],
        opts
      )
    )
  end

  defp codec do
    {:ok, codec} =
      ShardingIndexed.init(
        %{"chunk_shape" => [2, 2], "codecs" => [%{"name" => "bytes"}]},
        shard_shape: [4, 4],
        dtype: :int32
      )

    codec
  end

  describe "metadata geometry" do
    test "shard_shape: writes the shard shape to the chunk grid and the inner shape to the codec" do
      {:ok, array} = sharded_array(shape: {100, 120}, chunks: {4, 4}, shard_shape: {2, 3})

      assert array.chunks == {4, 4}
      assert array.metadata.chunk_grid.configuration.chunk_shape == {8, 12}
      [%{name: "sharding_indexed", configuration: config}] = array.metadata.codecs
      assert config.chunk_shape == [4, 4]

      assert [%{name: "bytes", configuration: %{endian: "little"}}, %{name: "crc32c"}] =
               config.index_codecs
    end

    test "explicit sharding codec: chunks is the shard shape, array.chunks the inner shape" do
      {:ok, array} =
        ExZarr.create(
          shape: {16, 16},
          chunks: {8, 8},
          dtype: :float32,
          zarr_version: 3,
          storage: :memory,
          codecs: [
            %{
              name: "sharding_indexed",
              configuration: %{chunk_shape: [2, 4], codecs: [%{name: "bytes"}]}
            }
          ]
        )

      assert array.chunks == {2, 4}
      assert array.metadata.chunk_grid.configuration.chunk_shape == {8, 8}
    end

    test "shard shape must be a multiple of the inner chunk shape" do
      assert {:error, {:invalid_sharding, _}} =
               ExZarr.create(
                 shape: {16, 16},
                 chunks: {8, 8},
                 dtype: :int32,
                 zarr_version: 3,
                 storage: :memory,
                 codecs: [
                   %{
                     name: "sharding_indexed",
                     configuration: %{chunk_shape: [3, 3], codecs: [%{name: "bytes"}]}
                   }
                 ]
               )
    end
  end

  describe "codec validation" do
    test "index codecs are limited to fixed-size codecs" do
      config = %{"chunk_shape" => [2], "codecs" => [%{"name" => "bytes"}]}

      for name <- ["gzip", "zstd", "transpose", "made_up"] do
        assert {:error, {:unsupported_index_codec, ^name}} =
                 ShardingIndexed.init(
                   Map.put(config, "index_codecs", [%{"name" => "bytes"}, %{"name" => name}])
                 )
      end

      assert {:error, {:invalid_index_codecs, :empty}} =
               ShardingIndexed.init(Map.put(config, "index_codecs", []))
    end

    test "functions that touch shard bytes need the shard shape" do
      {:ok, codec} =
        ShardingIndexed.init(%{"chunk_shape" => [2], "codecs" => [%{"name" => "bytes"}]})

      assert {:error, :shard_shape_required} = ShardingIndexed.encode(%{}, codec)
      assert {:error, :shard_shape_required} = ShardingIndexed.decode(<<>>, codec)
      assert {:error, :shard_shape_required} = ShardingIndexed.index_byte_range(codec, 100)
    end
  end

  describe "malformed shards" do
    property "decoding arbitrary bytes never raises" do
      codec = codec()

      check all(bytes <- StreamData.binary(max_length: 200)) do
        assert match?({:ok, _}, ShardingIndexed.decode(bytes, codec)) or
                 match?({:error, _}, ShardingIndexed.decode(bytes, codec))

        result = ShardingIndexed.decode_chunk(bytes, {1, 1}, codec)
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    property "reading an array over arbitrary shard bytes returns an error tuple" do
      {:ok, array} = sharded_array()

      check all(bytes <- StreamData.binary(min_length: 1, max_length: 300)) do
        :ok = Storage.write_chunk(array.storage, {0, 0}, bytes)
        result = Array.get_slice(array, start: {0, 0}, stop: {4, 4})
        assert match?({:ok, _}, result) or match?({:error, _}, result)
      end
    end

    test "inner chunks of the wrong size are rejected" do
      {:ok, array} = sharded_array()
      {:ok, codec} = codec_for(array)

      # A 2x2 int32 inner chunk is 16 bytes; store 12.
      {:ok, shard} = ShardingIndexed.encode(%{{0, 0} => :binary.copy(<<1>>, 12)}, codec)
      :ok = Storage.write_chunk(array.storage, {0, 0}, shard)

      assert {:error, {:invalid_chunk_size, %{expected: 16, actual: 12}}} =
               Array.get_slice(array, start: {0, 0}, stop: {2, 2})
    end

    test "writing into an undecodable shard fails instead of dropping its chunks" do
      {:ok, array} = sharded_array()
      garbage = :binary.copy(<<0xAB>>, 100)
      :ok = Storage.write_chunk(array.storage, {0, 0}, garbage)

      assert {:error, _} =
               Array.set_slice(array, :binary.copy(<<0>>, 16), start: {0, 0}, stop: {2, 2})

      assert {:ok, ^garbage} = Storage.read_chunk(array.storage, {0, 0})
    end
  end

  describe "pre-1.2.0 shards" do
    # The private layout: data, then an index starting with a uint32 chunk
    # count, then the index size as a trailing uint64.
    defp legacy_shard do
      data = :binary.copy(<<7>>, 16)

      index =
        <<1::little-32, 2::little-32, 0::little-signed-32, 0::little-signed-32, 0::little-64,
          16::little-64>>

      <<data::binary, index::binary, byte_size(index)::little-64>>
    end

    test "are detected" do
      assert ShardingIndexed.legacy_format?(legacy_shard(), :end)
      refute ShardingIndexed.legacy_format?(:binary.copy(<<0xFF>>, 64), :end)
    end

    test "reads return a migration error" do
      {:ok, array} = sharded_array()
      :ok = Storage.write_chunk(array.storage, {0, 0}, legacy_shard())

      assert {:error, {:legacy_shard_format, :rewrite_required}} =
               Array.get_slice(array, start: {0, 0}, stop: {2, 2})
    end

    test "writes return a migration error and leave the shard alone" do
      {:ok, array} = sharded_array()
      :ok = Storage.write_chunk(array.storage, {0, 0}, legacy_shard())

      assert {:error, {:legacy_shard_format, :rewrite_required}} =
               Array.set_slice(array, :binary.copy(<<0>>, 16), start: {0, 0}, stop: {2, 2})

      assert {:ok, shard} = Storage.read_chunk(array.storage, {0, 0})
      assert shard == legacy_shard()
    end
  end

  describe "unsupported data types" do
    test "opening reports unknown and extension data types instead of raising" do
      for data_type <- ["complex256", %{"name" => "my.custom_dtype", "configuration" => %{}}] do
        path = Path.join(System.tmp_dir!(), "ex_zarr_dtype_#{System.unique_integer([:positive])}")
        File.mkdir_p!(path)

        File.write!(
          Path.join(path, "zarr.json"),
          Jason.encode!(%{
            zarr_format: 3,
            node_type: "array",
            shape: [4],
            data_type: data_type,
            chunk_grid: %{name: "regular", configuration: %{chunk_shape: [4]}},
            chunk_key_encoding: %{name: "default"},
            codecs: [%{name: "bytes"}],
            fill_value: 0
          })
        )

        assert {:error, {:unsupported_data_type, _}} = ExZarr.open(path: path)
        File.rm_rf!(path)
      end
    end
  end

  describe "partial edge shards" do
    test "arrays whose shape is not a multiple of the shard shape round-trip" do
      {:ok, array} = sharded_array(shape: {7, 9}, chunks: {2, 3}, shard_shape: {2, 2})
      data = for i <- 0..62, into: <<>>, do: <<i::signed-little-32>>
      :ok = Array.set_slice(array, data, start: {0, 0}, stop: {7, 9})
      assert {:ok, ^data} = Array.get_slice(array, start: {0, 0}, stop: {7, 9})
      assert {:ok, <<62::little-32>>} = Array.get_slice(array, start: {6, 8}, stop: {7, 9})
    end
  end

  defp codec_for(array) do
    [%{configuration: config}] = array.metadata.codecs

    ShardingIndexed.init(config,
      shard_shape: array.metadata.chunk_grid.configuration.chunk_shape,
      dtype: array.dtype
    )
  end
end
