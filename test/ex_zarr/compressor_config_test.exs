defmodule ExZarr.CompressorConfigTest do
  # async: false because some tests change the :default_zarr_version app env
  use ExUnit.Case, async: false

  doctest ExZarr.Codecs.CompressorConfig

  alias ExZarr.Array
  alias ExZarr.Codecs.CompressorConfig

  setup do
    path = Path.join(System.tmp_dir!(), "ex_zarr_ccfg_#{System.unique_integer([:positive])}")
    on_exit(fn -> File.rm_rf!(path) end)
    {:ok, path: path}
  end

  defp data(n \\ 4_000),
    do: for(i <- 0..(n - 1), into: <<>>, do: <<rem(i, 50) * 1.0::float-little-64>>)

  defp create(path, opts) do
    ExZarr.create(
      Keyword.merge(
        [shape: {4_000}, chunks: {4_000}, dtype: :float64, storage: :filesystem, path: path],
        opts
      )
    )
  end

  defp json(path, file), do: path |> Path.join(file) |> File.read!() |> Jason.decode!()

  defp stored_chunk(array), do: ExZarr.Storage.read_chunk(array.storage, {0})

  describe "default_zarr_version" do
    setup do
      previous = Application.get_env(:ex_zarr, :default_zarr_version)

      on_exit(fn ->
        if previous,
          do: Application.put_env(:ex_zarr, :default_zarr_version, previous),
          else: Application.delete_env(:ex_zarr, :default_zarr_version)
      end)
    end

    test "unset: new arrays are v2" do
      Application.delete_env(:ex_zarr, :default_zarr_version)
      assert ExZarr.Version.default_version() == 2
      assert {:ok, %{version: 2}} = ExZarr.create(shape: {10}, chunks: {5})
    end

    test "configured: new arrays use it" do
      Application.put_env(:ex_zarr, :default_zarr_version, 3)

      assert {:ok, %{version: 3, metadata: %ExZarr.MetadataV3{}}} =
               ExZarr.create(shape: {10}, chunks: {5})
    end

    test "the zarr_version option still wins" do
      Application.put_env(:ex_zarr, :default_zarr_version, 3)
      assert {:ok, %{version: 2}} = ExZarr.create(shape: {10}, chunks: {5}, zarr_version: 2)
    end

    test "invalid versions are errors, not crashes" do
      assert {:error, {:invalid_zarr_version, 4}} =
               ExZarr.create(shape: {10}, chunks: {5}, zarr_version: 4)

      Application.put_env(:ex_zarr, :default_zarr_version, "3")

      assert {:error, {:invalid_zarr_version, "3"}} = ExZarr.create(shape: {10}, chunks: {5})
    end
  end

  describe "compressor_config on v2 arrays" do
    test "settings reach .zarray and survive reopen", %{path: path} do
      {:ok, array} = create(path, compressor: :zstd, compressor_config: [level: 19])
      :ok = Array.save(array, path: path)

      assert json(path, ".zarray")["compressor"] == %{"id" => "zstd", "level" => 19}
      assert {:ok, reopened} = ExZarr.open(path: path)
      assert reopened.metadata.compressor_config == [level: 19]
    end

    test "blosc settings are applied and kept for later writes", %{path: path} do
      {:ok, array} =
        create(path,
          compressor: :blosc,
          compressor_config: [cname: :zstd, shuffle: :bit, typesize: 8]
        )

      :ok = Array.save(array, path: path)
      :ok = Array.set_slice(array, data(), start: {0}, stop: {4_000})

      # Blosc1 header: compressor format in bits 5-7 (zstd = 4), bitshuffle flag 0x04
      {:ok, <<2, 1, flags, 8, _::binary>>} = stored_chunk(array)
      assert Bitwise.bsr(flags, 5) == 4
      assert Bitwise.band(flags, 0x04) == 0x04

      assert json(path, ".zarray")["compressor"] ==
               %{
                 "id" => "blosc",
                 "cname" => "zstd",
                 "clevel" => 5,
                 "shuffle" => 2,
                 "blocksize" => 0
               }

      # A later writer picks the settings up from .zarray.
      {:ok, reopened} = ExZarr.open(path: path)
      :ok = Array.set_slice(reopened, data(), start: {0}, stop: {4_000})
      {:ok, <<2, 1, flags2, _::binary>>} = stored_chunk(reopened)
      assert Bitwise.bsr(flags2, 5) == 4
      assert {:ok, data()} == Array.get_slice(reopened, start: {0}, stop: {4_000})
    end

    test "zlib honours the level", %{path: path} do
      sizes =
        for level <- [0, 9] do
          dir = Path.join(path, "l#{level}")
          {:ok, array} = create(dir, compressor: :zlib, compressor_config: [level: level])
          :ok = Array.set_slice(array, data(), start: {0}, stop: {4_000})
          {:ok, chunk} = stored_chunk(array)
          byte_size(chunk)
        end

      assert [stored, compressed] = sizes
      assert stored > byte_size(data())
      assert compressed < div(byte_size(data()), 10)
    end

    test "maps are accepted", %{path: path} do
      assert {:ok, array} = create(path, compressor: :bzip2, compressor_config: %{level: 3})
      assert array.metadata.compressor_config == [level: 3]
    end
  end

  describe "compressor_config on v3 arrays" do
    test "settings become the codec configuration", %{path: path} do
      {:ok, _} =
        create(path,
          zarr_version: 3,
          compressor: :blosc,
          compressor_config: [cname: :lz4, level: 7, shuffle: :bit, typesize: 8]
        )

      assert %{"name" => "blosc", "configuration" => config} =
               List.last(json(path, "zarr.json")["codecs"])

      assert config == %{
               "cname" => "lz4",
               "clevel" => 7,
               "shuffle" => "bitshuffle",
               "typesize" => 8
             }
    end

    test "gzip is a v3 compressor", %{path: path} do
      {:ok, array} =
        create(path, zarr_version: 3, compressor: :gzip, compressor_config: [level: 8])

      assert %{"name" => "gzip", "configuration" => %{"level" => 8}} =
               List.last(json(path, "zarr.json")["codecs"])

      :ok = Array.set_slice(array, data(), start: {0}, stop: {4_000})
      {:ok, <<0x1F, 0x8B, _::binary>>} = stored_chunk(array)
    end
  end

  describe "validation" do
    test "unknown or out-of-range settings are rejected" do
      for {compressor, config, reason} <- [
            {:zstd, [level: 30], {:invalid_value, :level, 30}},
            {:zlib, [level: -1], {:invalid_value, :level, -1}},
            {:lz4, [level: 1], {:unknown_option, :level}},
            {:snappy, [level: 1], {:unknown_option, :level}},
            {:zstd, [cname: :lz4], {:unknown_option, :cname}},
            {:blosc, [shuffle: :sideways], {:invalid_value, :shuffle, :sideways}},
            {:blosc, [cname: "snappy"], {:invalid_value, :cname, "snappy"}},
            {:zstd, [:level], :not_a_keyword_list}
          ] do
        assert {:error, {:invalid_compressor_config, ^compressor, ^reason}} =
                 ExZarr.create(
                   shape: {10},
                   chunks: {5},
                   compressor: compressor,
                   compressor_config: config
                 )
      end
    end

    test "unknown compressors fail at create, not at the first write" do
      assert {:error, {:unsupported_codec, :gzip}} =
               ExZarr.create(shape: {10}, chunks: {5}, compressor: :gzip)

      assert {:error, {:unsupported_codec, :brotli}} =
               ExZarr.create(shape: {10}, chunks: {5}, compressor: :brotli, zarr_version: 2)
    end

    test "v3 rejects compressors with no v3 codec instead of storing data uncompressed" do
      assert {:error, {:unsupported_codec_for_v3, :snappy}} =
               ExZarr.create(shape: {10}, chunks: {5}, compressor: :snappy, zarr_version: 3)
    end

    test "custom codec settings pass through unchanged" do
      assert {:ok, [threshold: 10]} = CompressorConfig.normalize(:my_codec, threshold: 10)
    end
  end
end
