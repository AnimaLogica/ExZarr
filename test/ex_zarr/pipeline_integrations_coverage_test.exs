defmodule ExZarr.PipelineIntegrationsCoverageTest do
  use ExUnit.Case, async: true

  setup do
    {:ok, array} =
      ExZarr.create(
        shape: {4},
        chunks: {2},
        dtype: :int32,
        storage: :memory,
        compressor: :none
      )

    chunk = <<1, 0, 0, 0, 2, 0, 0, 0>>
    :ok = ExZarr.Array.set_slice(array, chunk, start: {0}, stop: {2})
    :ok = ExZarr.Array.set_slice(array, chunk, start: {2}, stop: {4})
    %{array: array}
  end

  test "Flow.slice_flow yields slices", %{array: array} do
    sizes =
      array
      |> ExZarr.Flow.slice_flow(0, stages: 1)
      |> Flow.map(fn {_start, data} -> byte_size(data) end)
      |> Enum.to_list()

    assert length(sizes) >= 1
    assert Enum.all?(sizes, &(&1 > 0))
  end

  test "GenStage slice producer exhausts", %{array: array} do
    {:ok, producer} = ExZarr.GenStage.start_slice_producer(array, 0)

    {:ok, agent} = Agent.start_link(fn -> [] end)

    try do
      [{producer, max_demand: 1}]
      |> GenStage.stream()
      |> Stream.each(fn event -> Agent.update(agent, &[event | &1]) end)
      |> Stream.run()
    catch
      :exit, {:normal, {GenStage, :close_stream, _}} -> :ok
    end

    events = Agent.get(agent, &Enum.reverse/1)
    Agent.stop(agent)

    assert length(events) >= 1
    refute Process.alive?(producer)
  end

  test "Broadway.chunk_pipeline_options builds a producer config", %{array: array} do
    opts = ExZarr.Broadway.chunk_pipeline_options(__MODULE__.DummyBroadway, array, concurrency: 2)

    assert opts[:name] == __MODULE__.DummyBroadway
    assert opts[:processors][:default][:concurrency] == 2
    assert {ExZarr.Broadway.ChunkProducer, _} = opts[:producer][:module]
  end
end
