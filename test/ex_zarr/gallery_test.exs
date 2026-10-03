defmodule ExZarr.GalleryTest do
  use ExUnit.Case, async: true

  alias ExZarr.Gallery.{Metrics, Pack, SampleData}

  describe "Pack" do
    test "round-trips integers and floats" do
      ints = [1, -2, 3, 0]
      floats = [1.5, -2.25, 0.0]
      uints = [0, 1, 255]

      assert Pack.unpack(Pack.pack(ints, :int32), :int32) == ints
      assert Pack.unpack(Pack.pack(ints, :int8), :int8) == ints
      assert Pack.unpack(Pack.pack(ints, :int16), :int16) == ints
      assert Pack.unpack(Pack.pack(ints, :int64), :int64) == ints
      assert Pack.unpack(Pack.pack(uints, :uint8), :uint8) == uints
      assert Pack.unpack(Pack.pack([0, 1, 2], :uint16), :uint16) == [0, 1, 2]
      assert Pack.unpack(Pack.pack([0, 1, 2], :uint32), :uint32) == [0, 1, 2]
      assert Pack.unpack(Pack.pack([0, 1, 2], :uint64), :uint64) == [0, 1, 2]
      assert Pack.unpack(Pack.pack(floats, :float64), :float64) == floats
      assert Pack.unpack(Pack.pack(floats, :float32), :float32) == floats
      assert Pack.itemsize(:float32) == 4
      assert Pack.itemsize(:uint64) == 8
    end

    test "rejects mis-sized unpack binary" do
      assert_raise ArgumentError, fn -> Pack.unpack(<<1, 2, 3>>, :int32) end
    end
  end

  describe "SampleData" do
    test "matrix pattern and corpus" do
      assert SampleData.matrix(2, 3) == [0, 1, 2, 1000, 1001, 1002]
      assert length(SampleData.rand_floats(5, 7)) == 5
      assert length(SampleData.tiny_corpus()) == 5
    end
  end

  describe "Metrics" do
    test "times a function and formats durations" do
      {result, us} = Metrics.time(fn -> :ok end)
      assert result == :ok
      assert is_integer(us) and us >= 0
      assert Metrics.human_us(500) == "500µs"
      assert Metrics.human_us(2_500) =~ "ms"
      assert Metrics.human_us(2_500_000) =~ "s"
    end
  end
end
