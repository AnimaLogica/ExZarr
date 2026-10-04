defmodule ExZarr.Codecs.CodecFormatsTest do
  @moduledoc """
  On-disk codec formats after moving the built-in codecs to ExCodecs.

  * `legacy_codecs/` holds bytes written by ExZarr's Zig NIFs (1.1.x and the
    1.2 development line). They must keep decoding.
  * `numcodecs/` holds bytes written by numcodecs (zarr-python); see
    `test/fixtures/numcodecs/generate.py`.
  """
  # async: false because one test changes the :max_chunk_bytes app env
  use ExUnit.Case, async: false

  alias ExZarr.Codecs

  @legacy_dir Path.expand("../../fixtures/legacy_codecs", __DIR__)
  @numcodecs_dir Path.expand("../../fixtures/numcodecs", __DIR__)

  # Same payload both fixture generators use.
  @payload for i <- 0..39_999, into: <<>>, do: <<rem(i * 7 + div(i, 3), 251)>>

  defp fixture(dir, name), do: File.read!(Path.join(dir, name <> ".bin"))

  describe "data written by the Zig NIF codecs" do
    for codec <- [:zstd, :lz4, :snappy, :blosc, :bzip2, :crc32c, :zlib] do
      test "#{codec} still decodes" do
        bin = fixture(@legacy_dir, unquote(Atom.to_string(codec)))
        assert {:ok, @payload} = Codecs.decompress(bin, unquote(codec))
      end
    end

    test "legacy lz4 and bzip2 used an 8-byte size prefix" do
      for codec <- ["lz4", "bzip2"] do
        assert <<40_000::64-little, _::binary>> = fixture(@legacy_dir, codec)
      end
    end
  end

  describe "data written by numcodecs (zarr-python)" do
    for {name, codec} <- [
          {"zstd", :zstd},
          {"lz4", :lz4},
          {"bz2", :bzip2},
          {"blosc_blosclz_shuffle", :blosc},
          {"blosc_lz4_bitshuffle", :blosc},
          {"blosc_zstd_noshuffle", :blosc}
        ] do
      test "#{name} decodes" do
        bin = fixture(@numcodecs_dir, unquote(name))
        assert {:ok, @payload} = Codecs.decompress(bin, unquote(codec))
      end
    end
  end

  describe "formats written now" do
    test "lz4 uses numcodecs' 4-byte little-endian size prefix" do
      assert {:ok, <<40_000::32-little, _block::binary>>} = Codecs.compress(@payload, :lz4)
    end

    test "bzip2 is a plain bzip2 stream" do
      assert {:ok, <<"BZh9", _::binary>>} = Codecs.compress(@payload, :bzip2)
      assert {:ok, <<"BZh1", _::binary>>} = Codecs.compress(@payload, :bzip2, level: 1)
    end

    test "blosc writes Blosc1 chunks with ExZarr's historical defaults" do
      assert {:ok, <<2, 1, flags, 1, 40_000::32-little, _::binary>>} =
               Codecs.compress(@payload, :blosc)

      # BloscLZ (format 0), byte shuffle
      assert Bitwise.bsr(flags, 5) == 0
      assert Bitwise.band(flags, 0x01) == 0x01
    end

    test "blosc honours cname, shuffle and typesize" do
      assert {:ok, <<2, 1, flags, 8, _::binary>> = chunk} =
               Codecs.compress(@payload, :blosc, cname: :zstd, shuffle: :bit, typesize: 8)

      assert Bitwise.bsr(flags, 5) == 4
      assert Bitwise.band(flags, 0x04) == 0x04
      assert {:ok, @payload} = Codecs.decompress(chunk, :blosc)
    end

    test "crc32c appends a little-endian checksum" do
      assert {:ok, "123456789" <> <<0x83, 0x92, 0x06, 0xE3>>} =
               Codecs.compress("123456789", :crc32c)
    end

    test "map options are accepted like keyword options" do
      assert {:ok, <<"BZh1", _::binary>>} = Codecs.compress(@payload, :bzip2, %{level: 1})
    end
  end

  describe "v3 pipeline" do
    alias ExZarr.Codecs.PipelineV3

    test "blosc configuration from zarr.json is applied" do
      {:ok, pipeline} =
        PipelineV3.parse_codecs([
          %{name: "bytes", configuration: %{endian: "little"}},
          %{
            name: "blosc",
            configuration: %{
              "cname" => "lz4",
              "clevel" => 7,
              "shuffle" => "bitshuffle",
              "typesize" => 4
            }
          }
        ])

      {:ok, <<2, 1, flags, 4, _::binary>> = chunk} = PipelineV3.encode(@payload, pipeline)
      assert Bitwise.bsr(flags, 5) == 1
      assert Bitwise.band(flags, 0x04) == 0x04
      assert {:ok, @payload} = PipelineV3.decode(chunk, pipeline)
    end
  end

  describe "v2 compressor metadata" do
    setup do
      path = Path.join(System.tmp_dir!(), "ex_zarr_v2meta_#{System.unique_integer([:positive])}")
      on_exit(fn -> File.rm_rf!(path) end)
      {:ok, path: path}
    end

    defp zarray(path), do: path |> Path.join(".zarray") |> File.read!() |> Jason.decode!()

    defp write_v2(path, compressor) do
      {:ok, array} =
        ExZarr.create(
          shape: {20},
          chunks: {10},
          dtype: :float64,
          compressor: compressor,
          storage: :filesystem,
          path: path
        )

      :ok = ExZarr.Array.save(array, path: path)
      array
    end

    test "uses numcodecs ids and configurations", %{path: path} do
      for {compressor, expected} <- [
            lz4: %{"id" => "lz4", "acceleration" => 1},
            bzip2: %{"id" => "bz2", "level" => 9},
            blosc: %{
              "id" => "blosc",
              "cname" => "blosclz",
              "clevel" => 5,
              "shuffle" => 1,
              "blocksize" => 0
            },
            zstd: %{"id" => "zstd", "level" => 3}
          ] do
        dir = Path.join(path, Atom.to_string(compressor))
        write_v2(dir, compressor)
        assert zarray(dir)["compressor"] == expected
      end
    end

    test "arrays written with the old \"bzip2\" id still open", %{path: path} do
      data = for i <- 0..19, into: <<>>, do: <<i * 1.0::float-little-64>>
      array = write_v2(path, :bzip2)
      :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {20})

      meta = zarray(path) |> Map.put("compressor", %{"id" => "bzip2", "level" => 5})
      File.write!(Path.join(path, ".zarray"), Jason.encode!(meta))

      {:ok, reopened} = ExZarr.open(path: path)
      assert reopened.compressor == :bzip2
      assert {:ok, ^data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {20})
    end
  end

  describe "decoded chunk size limit" do
    test "max_chunk_bytes caps decompressed output" do
      {:ok, compressed} = Codecs.compress(@payload, :zstd)
      previous = Application.get_env(:ex_zarr, :max_chunk_bytes)
      Application.put_env(:ex_zarr, :max_chunk_bytes, 1_000)

      try do
        assert {:error, {:decompression_failed, :output_limit_exceeded}} =
                 Codecs.decompress(compressed, :zstd)
      after
        if previous,
          do: Application.put_env(:ex_zarr, :max_chunk_bytes, previous),
          else: Application.delete_env(:ex_zarr, :max_chunk_bytes)
      end
    end
  end
end
