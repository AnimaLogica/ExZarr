defmodule ExZarr.Storage.BackendRangeMoxTest do
  use ExUnit.Case, async: true

  import Mox

  alias ExZarr.Storage.Backend

  setup :verify_on_exit!

  defmock(RangeCapableBackend, for: Backend)
  defmock(NoRangeBackend, for: Backend)

  setup do
    %{state: %{id: System.unique_integer([:positive])}}
  end

  describe "Backend.supports?/3 via Mox" do
    test "capabilities MapSet advertises :range_read", %{state: state} do
      expect(RangeCapableBackend, :capabilities, 2, fn ^state ->
        MapSet.new([:range_read])
      end)

      assert Backend.supports?(RangeCapableBackend, state, :range_read)
      refute Backend.supports?(RangeCapableBackend, state, :multipart)
    end

    test "capabilities list advertises :range_read", %{state: state} do
      expect(RangeCapableBackend, :capabilities, fn ^state -> [:range_read] end)
      assert Backend.supports?(RangeCapableBackend, state, :range_read)
    end

    test "invalid capabilities return false", %{state: state} do
      expect(RangeCapableBackend, :capabilities, fn ^state -> :not_a_collection end)
      refute Backend.supports?(RangeCapableBackend, state, :range_read)
    end
  end

  describe "Backend.read_range/6 via Mox" do
    test "uses read_chunk_range/5 when available", %{state: state} do
      expect(RangeCapableBackend, :capabilities, fn ^state -> MapSet.new([:range_read]) end)

      expect(RangeCapableBackend, :read_chunk_range, fn ^state, {0}, 2, 3, opts ->
        assert opts[:if_match] == "etag-1"
        {:ok, <<2, 3, 4>>}
      end)

      assert {:ok, <<2, 3, 4>>} =
               Backend.read_range(RangeCapableBackend, state, {0}, 2, 3, if_match: "etag-1")
    end

    test "zero length returns empty binary without calling backend", %{state: state} do
      assert {:ok, ""} = Backend.read_range(RangeCapableBackend, state, {0}, 0, 0)
    end

    test "falls back to full read_chunk when range is unsupported", %{state: state} do
      # supports?/3 is evaluated twice in read_range/6's cond
      expect(NoRangeBackend, :capabilities, 2, fn ^state -> MapSet.new() end)

      expect(NoRangeBackend, :read_chunk, fn ^state, {0} ->
        {:ok, <<0, 1, 2, 3, 4, 5>>}
      end)

      assert {:ok, <<2, 3, 4>>} = Backend.read_range(NoRangeBackend, state, {0}, 2, 3)
    end

    test "propagates read_chunk errors on fallback", %{state: state} do
      expect(NoRangeBackend, :capabilities, 2, fn ^state -> [] end)
      expect(NoRangeBackend, :read_chunk, fn ^state, {0} -> {:error, :not_found} end)

      assert {:error, :not_found} = Backend.read_range(NoRangeBackend, state, {0}, 0, 1)
    end

    test "validates overlong range body by local slice", %{state: state} do
      expect(RangeCapableBackend, :capabilities, fn ^state -> MapSet.new([:range_read]) end)

      expect(RangeCapableBackend, :read_chunk_range, fn ^state, {0}, 1, 2, _opts ->
        {:ok, <<0, 1, 2, 3, 4>>}
      end)

      assert {:ok, <<1, 2>>} = Backend.read_range(RangeCapableBackend, state, {0}, 1, 2)
    end

    test "rejects short range body", %{state: state} do
      expect(RangeCapableBackend, :capabilities, fn ^state -> MapSet.new([:range_read]) end)

      expect(RangeCapableBackend, :read_chunk_range, fn ^state, {0}, 0, 4, _opts ->
        {:ok, <<1, 2>>}
      end)

      assert {:error, {:invalid_chunk_range, _}} =
               Backend.read_range(RangeCapableBackend, state, {0}, 0, 4)
    end

    test "chunk_info and put_layout optional callbacks", %{state: state} do
      expect(RangeCapableBackend, :chunk_info, fn ^state, {1, 2} ->
        {:ok, %{size: 16, etag: "abc"}}
      end)

      expect(RangeCapableBackend, :put_layout, fn ^state, layout ->
        assert layout.zarr_format == 3
        Map.merge(state, layout)
      end)

      assert {:ok, %{size: 16, etag: "abc"}} = RangeCapableBackend.chunk_info(state, {1, 2})

      assert %{zarr_format: 3, chunk_key_encoding: nil} =
               RangeCapableBackend.put_layout(state, %{
                 zarr_format: 3,
                 chunk_key_encoding: nil
               })
    end
  end
end
