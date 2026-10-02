defmodule ExZarr.StreamingProducerCoverageTest do
  use ExUnit.Case, async: true

  alias ExZarr.Streaming.Producer

  setup do
    {:ok, array} =
      ExZarr.create(
        shape: {4, 4},
        chunks: {2, 2},
        dtype: :int32,
        storage: :memory,
        compressor: :none
      )

    data = for _ <- 1..4, into: <<>>, do: <<1::signed-little-32>>
    :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {2, 2})
    :ok = ExZarr.Array.set_slice(array, data, start: {0, 2}, stop: {2, 4})
    :ok = ExZarr.Array.set_slice(array, data, start: {2, 0}, stop: {4, 2})
    :ok = ExZarr.Array.set_slice(array, data, start: {2, 2}, stop: {4, 4})

    %{array: array}
  end

  test "chunk_init/demand drains remaining chunks", %{array: array} do
    state = Producer.chunk_init(array, [])
    assert length(state.remaining) == 4

    {events, state2} = Producer.chunk_demand(2, state)
    assert length(events) == 2
    assert length(state2.remaining) == 2

    {events2, state3} = Producer.chunk_demand(10, state2)
    assert length(events2) == 2
    assert state3.remaining == []
  end

  test "slice_init/demand drains remaining slices", %{array: array} do
    state = Producer.slice_init(array, 0, [])
    assert Enum.empty?(state.remaining) == false

    {events, state2} = Producer.slice_demand(1, state)
    assert length(events) == 1
    assert length(state2.remaining) == length(state.remaining) - 1
  end
end
