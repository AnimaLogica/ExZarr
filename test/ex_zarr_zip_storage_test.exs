defmodule ExZarr.ZipStorageTest do
  use ExUnit.Case

  describe "Zip storage backend" do
    test "create and save array with zip storage" do
      path = "/tmp/test_zip_#{:rand.uniform(1_000_000)}.zip"

      try do
        # Create array with zip storage
        {:ok, array} =
          ExZarr.create(
            shape: {100},
            chunks: {20},
            dtype: :int32,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        # Write data
        data =
          for i <- 0..99, into: <<>> do
            <<i::signed-little-32>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})

        # Save to zip file
        :ok = ExZarr.save(array, path: path)

        # Verify zip file was created
        assert File.exists?(path)

        # Verify it's a valid zip file
        {:ok, zip_files} = :zip.list_dir(to_charlist(path))

        filenames =
          zip_files
          |> Enum.filter(fn
            {:zip_file, _, _, _, _, _} -> true
            _ -> false
          end)
          |> Enum.map(fn {:zip_file, name, _, _, _, _} -> to_string(name) end)

        assert ".zarray" in filenames
        # Should have metadata + chunks
        assert length(filenames) > 1
      after
        File.rm(path)
      end
    end

    test "open and read array from zip storage" do
      path = "/tmp/test_zip_read_#{:rand.uniform(1_000_000)}.zip"

      try do
        # Create and save array
        {:ok, array} =
          ExZarr.create(
            shape: {50},
            chunks: {10},
            dtype: :float64,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data =
          for i <- 0..49, into: <<>> do
            value = i * 1.5
            <<value::float-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {50})
        :ok = ExZarr.save(array, path: path)

        # Open the zip file
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)

        # Read data back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {50})

        assert read_data == data
      after
        File.rm(path)
      end
    end

    test "zip storage with multiple chunks" do
      path = "/tmp/test_zip_chunks_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {500},
            chunks: {100},
            dtype: :int64,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data =
          for i <- 0..499, into: <<>> do
            <<i::signed-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {500})
        :ok = ExZarr.save(array, path: path)

        # Reopen and read
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {500})

        assert read_data == data

        # Read partial slice crossing chunk boundary
        {:ok, partial} = ExZarr.Array.get_slice(reopened, start: {95}, stop: {105})

        expected =
          for i <- 95..104, into: <<>> do
            <<i::signed-little-64>>
          end

        assert partial == expected
      after
        File.rm(path)
      end
    end

    test "zip storage with filters" do
      path = "/tmp/test_zip_filters_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {100},
            chunks: {20},
            dtype: :int64,
            filters: [{:delta, [dtype: :int64]}],
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data =
          for i <- 0..99, into: <<>> do
            <<i::signed-little-64>>
          end

        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {100})
        :ok = ExZarr.save(array, path: path)

        # Reopen and verify filters are preserved
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)

        assert reopened.metadata.filters == [{:delta, [dtype: :int64, astype: :int64]}]

        # Read data back
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {100})

        assert read_data == data
      after
        File.rm(path)
      end
    end

    test "zip storage preserves metadata" do
      path = "/tmp/test_zip_metadata_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {200, 150},
            chunks: {50, 30},
            dtype: :float32,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        :ok = ExZarr.save(array, path: path)

        # Reopen and verify metadata
        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)

        assert reopened.metadata.shape == {200, 150}
        assert reopened.metadata.chunks == {50, 30}
        assert reopened.metadata.dtype == :float32
        assert reopened.metadata.zarr_format == 2
      after
        File.rm(path)
      end
    end

    test "zip storage with different dtypes" do
      dtypes = [
        :int8,
        :int16,
        :int32,
        :int64,
        :uint8,
        :uint16,
        :uint32,
        :uint64,
        :float32,
        :float64
      ]

      Enum.each(dtypes, fn dtype ->
        path = "/tmp/test_zip_#{dtype}_#{:rand.uniform(1_000_000)}.zip"

        try do
          {:ok, array} =
            ExZarr.create(
              shape: {10},
              chunks: {10},
              dtype: dtype,
              compressor: :zlib,
              storage: :zip,
              path: path
            )

          # Create appropriate test data for the dtype
          data =
            case dtype do
              dt when dt in [:int8, :int16, :int32, :int64] ->
                for i <- 0..9, into: <<>> do
                  case dt do
                    :int8 -> <<i::signed-little-8>>
                    :int16 -> <<i * 10::signed-little-16>>
                    :int32 -> <<i * 100::signed-little-32>>
                    :int64 -> <<i * 1000::signed-little-64>>
                  end
                end

              dt when dt in [:uint8, :uint16, :uint32, :uint64] ->
                for i <- 0..9, into: <<>> do
                  case dt do
                    :uint8 -> <<i::unsigned-little-8>>
                    :uint16 -> <<i * 10::unsigned-little-16>>
                    :uint32 -> <<i * 100::unsigned-little-32>>
                    :uint64 -> <<i * 1000::unsigned-little-64>>
                  end
                end

              dt when dt in [:float32, :float64] ->
                for i <- 0..9, into: <<>> do
                  value = i * 1.5

                  case dt do
                    :float32 -> <<value::float-little-32>>
                    :float64 -> <<value::float-little-64>>
                  end
                end
            end

          :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {10})
          :ok = ExZarr.save(array, path: path)

          # Reopen and verify
          {:ok, reopened} = ExZarr.open(path: path, storage: :zip)
          {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {10})

          assert read_data == data
        after
          File.rm_rf(path)
        end
      end)
    end

    test "save without path flushes zip cache to configured archive" do
      path = "/tmp/test_zip_flush_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {20},
            chunks: {10},
            dtype: :int32,
            compressor: :zlib,
            storage: :zip,
            path: path
          )

        data = for i <- 0..19, into: <<>>, do: <<i::signed-little-32>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {20})

        # No :path — zip backend writes metadata (and archive) in place
        assert :ok = ExZarr.save(array, [])
        assert File.regular?(path)

        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {20})
        assert read_data == data
      after
        File.rm_rf(path)
      end
    end

    test "save memory array to .zip path creates zip archive" do
      path = "/tmp/test_memory_to_zip_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {16},
            chunks: {8},
            dtype: :uint16,
            compressor: :zlib,
            storage: :memory
          )

        data = for i <- 0..15, into: <<>>, do: <<i::unsigned-little-16>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {16})

        assert :ok = ExZarr.save(array, path: path)
        assert File.regular?(path)

        {:ok, reopened} = ExZarr.open(path: path, storage: :zip)
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {16})
        assert read_data == data
      after
        File.rm_rf(path)
      end
    end

    test "save zip array to a different .zip path copies archive" do
      src = "/tmp/test_zip_src_#{:rand.uniform(1_000_000)}.zip"
      dest = "/tmp/test_zip_dest_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, array} =
          ExZarr.create(
            shape: {12},
            chunks: {6},
            dtype: :int32,
            compressor: :zlib,
            storage: :zip,
            path: src
          )

        data = for i <- 0..11, into: <<>>, do: <<i * 3::signed-little-32>>
        :ok = ExZarr.Array.set_slice(array, data, start: {0}, stop: {12})

        assert :ok = ExZarr.save(array, path: dest)
        assert File.regular?(dest)

        {:ok, reopened} = ExZarr.open(path: dest, storage: :zip)
        {:ok, read_data} = ExZarr.Array.get_slice(reopened, start: {0}, stop: {12})
        assert read_data == data
      after
        File.rm_rf(src)
        File.rm_rf(dest)
      end
    end

    test "save rejects empty path" do
      {:ok, array} =
        ExZarr.create(
          shape: {4},
          chunks: {4},
          dtype: :int32,
          storage: :memory
        )

      assert {:error, :invalid_path} = ExZarr.save(array, path: "")
    end

    test "zip backend rejects missing or invalid paths" do
      alias ExZarr.Storage.Backend.Zip

      assert {:error, :path_required} = Zip.init([])
      assert {:error, :path_required} = Zip.init(path: nil)
      assert {:error, :invalid_path} = Zip.init(path: :not_a_string)

      assert {:error, :path_required} = Zip.open([])

      assert {:error, :not_found} =
               Zip.open(path: "/tmp/exzarr_missing_#{:rand.uniform(1_000_000)}.zip")

      assert false == Zip.exists?([])
      assert false == Zip.exists?(path: "/tmp/exzarr_missing_#{:rand.uniform(1_000_000)}.zip")
    end

    test "zip open ignores unknown archive entries and rejects corrupt files" do
      alias ExZarr.Storage.Backend.Zip

      path = "/tmp/test_zip_extra_#{:rand.uniform(1_000_000)}.zip"
      bad_path = "/tmp/test_zip_corrupt_#{:rand.uniform(1_000_000)}.zip"

      try do
        {:ok, {_name, zip_bin}} =
          :zip.create(
            ~c"extra.zip",
            [
              {~c".zarray",
               ~s({"zarr_format":2,"shape":[4],"chunks":[4],"dtype":"<i4","compressor":null,"fill_value":0,"order":"C","filters":null,"dimension_separator":"."})},
              {~c"0", <<1, 0, 0, 0, 2, 0, 0, 0, 3, 0, 0, 0, 4, 0, 0, 0>>},
              {~c"README.txt", "not a chunk"}
            ],
            [:memory]
          )

        File.write!(path, zip_bin)
        assert {:ok, _state} = Zip.open(path: path)

        File.write!(bad_path, "this is not a zip file")
        assert {:error, {:zip_error, _}} = Zip.open(path: bad_path)
      after
        File.rm_rf(path)
        File.rm_rf(bad_path)
      end
    end
  end
end
