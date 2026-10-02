defmodule ExZarr.Storage.RangeReadTest do
  # Not async: tests attach telemetry handlers and change application env.
  use ExUnit.Case, async: false

  alias ExZarr.Array
  alias ExZarr.Storage
  alias ExZarr.Storage.Backend

  # Scriptable in-memory backend that records every call.
  #
  # Behaviour switches (in the shared Agent state):
  #   :range?      - advertise :range_read (default true)
  #   :ignore_range - answer range reads with the whole object
  #   :short       - answer range reads with one byte too few
  #   :swap_once   - binary to install as shard {0, 0} right after the index read
  #   :sleep_ms    - delay inner-chunk range reads
  defmodule ScriptedBackend do
    @behaviour ExZarr.Storage.Backend

    def backend_id, do: :range_scripted
    def init(config), do: {:ok, %{agent: Keyword.fetch!(config, :agent)}}
    def open(config), do: init(config)

    def read_chunk(%{agent: agent}, index) do
      log(agent, {:read_chunk, index})

      case Agent.get(agent, &Map.get(&1.objects, index)) do
        nil -> {:error, :not_found}
        data -> {:ok, data}
      end
    end

    def write_chunk(%{agent: agent}, index, data) do
      Agent.update(agent, &put_in(&1, [:objects, index], data))
    end

    def read_metadata(_state), do: {:error, :not_found}
    def write_metadata(_state, _metadata, _opts), do: :ok
    def list_chunks(%{agent: agent}), do: {:ok, Agent.get(agent, &Map.keys(&1.objects))}

    def delete_chunk(%{agent: agent}, index),
      do: Agent.update(agent, &(pop_in(&1, [:objects, index]) |> elem(1)))

    def exists?(_config), do: true

    def capabilities(%{agent: agent}) do
      if Agent.get(agent, &Map.get(&1, :range?, true)), do: [:range_read], else: []
    end

    def chunk_info(%{agent: agent}, index) do
      log(agent, {:chunk_info, index})

      case Agent.get(agent, &Map.get(&1.objects, index)) do
        nil -> {:error, :not_found}
        data -> {:ok, %{size: byte_size(data), etag: :erlang.phash2(data)}}
      end
    end

    def read_chunk_range(state, index, offset, length),
      do: read_chunk_range(state, index, offset, length, [])

    def read_chunk_range(%{agent: agent}, index, offset, length, opts) do
      log(agent, {:range, index, offset, length, opts})
      script = Agent.get(agent, & &1)

      if script[:sleep_ms] && offset == 0 && script[:index_at_end?],
        do: Process.sleep(script.sleep_ms)

      data = Map.fetch!(script.objects, index)

      cond do
        opts[:if_match] && opts[:if_match] != :erlang.phash2(data) ->
          {:error, :precondition_failed}

        script[:ignore_range] ->
          {:ok, data}

        script[:short] ->
          {:ok, binary_part(data, offset, length - 1)}

        true ->
          result = {:ok, binary_part(data, offset, length)}

          if swap = script[:swap_once] do
            Agent.update(
              agent,
              &(&1 |> Map.delete(:swap_once) |> put_in([:objects, index], swap))
            )
          end

          result
      end
    end

    defp log(agent, entry),
      do: Agent.update(agent, &Map.update!(&1, :log, fn log -> [entry | log] end))
  end

  setup do
    ExZarr.Storage.Registry.register(ScriptedBackend)
    {:ok, agent} = Agent.start_link(fn -> %{objects: %{}, log: []} end)

    test_pid = self()
    handler = "range-read-test-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:ex_zarr, :shard, :range_read],
      fn _event, measurements, metadata, _ ->
        send(test_pid, {:shard_read, measurements, metadata})
      end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    # 8x8 int32 array, inner chunks 2x2, 2x2 inner chunks per shard (shard 4x4).
    {:ok, array} =
      ExZarr.create(
        shape: {8, 8},
        chunks: {2, 2},
        shard_shape: {2, 2},
        dtype: :int32,
        zarr_version: 3,
        storage: :range_scripted,
        agent: agent
      )

    data = for i <- 0..63, into: <<>>, do: <<i::signed-little-32>>
    :ok = Array.set_slice(array, data, start: {0, 0}, stop: {8, 8})
    Agent.update(agent, &%{&1 | log: []})

    {:ok, array: array, agent: agent, data: data}
  end

  defp calls(agent), do: agent |> Agent.get(& &1.log) |> Enum.reverse()
  defp script(agent, changes), do: Agent.update(agent, &Map.merge(&1, changes))

  # Elements [0..1] x [0..1]: inner chunk {0, 0} of shard {0, 0}.
  defp first_chunk(array), do: Array.get_slice(array, start: {0, 0}, stop: {2, 2})
  defp expected_first_chunk, do: <<0::little-32, 1::little-32, 8::little-32, 9::little-32>>

  test "reads only the shard index and the needed inner chunk", %{array: array, agent: agent} do
    assert {:ok, data} = first_chunk(array)
    assert data == expected_first_chunk()

    log = calls(agent)
    refute Enum.any?(log, &match?({:read_chunk, _}, &1))
    ranges = for {:range, {0, 0}, offset, length, opts} <- log, do: {offset, length, opts}
    assert length(ranges) == 2
    assert Enum.all?(ranges, fn {_, _, opts} -> Keyword.has_key?(opts, :if_match) end)

    assert_receive {:shard_read, %{range_count: 2} = measurements,
                    %{fallback: false, fallback_reason: nil}}

    [{_, payload_len, _}] = Enum.reject(ranges, fn {_, length, _} -> length == 68 end)
    assert measurements.bytes_requested == payload_len
    # index: 4 inner chunks x 16 bytes + 4-byte crc32c
    assert measurements.bytes_fetched == payload_len + 68
  end

  test "falls back to a full shard read without range support", %{array: array, agent: agent} do
    script(agent, %{range?: false})

    assert {:ok, data} = first_chunk(array)
    assert data == expected_first_chunk()
    assert [{:read_chunk, {0, 0}}] = calls(agent)

    assert_receive {:shard_read, %{range_count: 1},
                    %{fallback: true, fallback_reason: :no_range_support}}
  end

  test "slices locally when the server ignores Range", %{array: array, agent: agent} do
    script(agent, %{ignore_range: true})
    assert {:ok, data} = first_chunk(array)
    assert data == expected_first_chunk()
  end

  test "short range bodies are rejected and the read falls back", %{array: array, agent: agent} do
    script(agent, %{short: true})

    assert {:ok, data} = first_chunk(array)
    assert data == expected_first_chunk()

    assert_receive {:shard_read, _, %{fallback: true, fallback_reason: {:invalid_chunk_range, _}}}
  end

  test "a shard rewritten mid-read is re-read, never mixed", %{array: array, agent: agent} do
    {:ok, other} =
      ExZarr.create(
        shape: {8, 8},
        chunks: {2, 2},
        shard_shape: {2, 2},
        dtype: :int32,
        zarr_version: 3,
        storage: :memory
      )

    new_data = for i <- 0..63, into: <<>>, do: <<i + 1000::signed-little-32>>
    :ok = Array.set_slice(other, new_data, start: {0, 0}, stop: {8, 8})
    {:ok, new_shard} = Storage.read_chunk(other.storage, {0, 0})

    # The shard changes right after its index is read.
    script(agent, %{swap_once: new_shard})

    assert {:ok, data} = first_chunk(array)

    assert data ==
             <<1000::little-32, 1001::little-32, 1008::little-32, 1009::little-32>>

    assert Enum.any?(calls(agent), &match?({:chunk_info, _}, &1))
    assert length(for {:chunk_info, _} <- calls(agent), do: 1) == 2
  end

  test "a stalled range request does not crash the caller", %{array: array, agent: agent} do
    previous = Application.get_env(:ex_zarr, :range_read_timeout)
    Application.put_env(:ex_zarr, :range_read_timeout, 50)
    on_exit(fn -> restore_env(:range_read_timeout, previous) end)

    # Inner chunk {0, 0} sits at offset 0 when the index is at the end.
    script(agent, %{sleep_ms: 300, index_at_end?: true})

    assert {:ok, data} = first_chunk(array)
    assert data == expected_first_chunk()

    assert_receive {:shard_read, _, %{fallback: true, fallback_reason: {:task_exit, :timeout}}}
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

    state = %{data: <<0, 1, 2, 3, 4, 5, 6, 7>>}

    assert {:ok, <<2, 3, 4>>} =
             Backend.read_range(NoRangeBackend, state, {0}, 2, 3)

    assert {:error, {:invalid_chunk_range, _}} =
             Backend.read_range(NoRangeBackend, state, {0}, 6, 3)
  end

  test "capabilities may be a MapSet or a list" do
    defmodule ListCaps do
      def capabilities(_), do: [:range_read]
    end

    defmodule SetCaps do
      def capabilities(_), do: MapSet.new([:range_read])
    end

    defmodule MapCaps do
      def capabilities(_), do: %{range_read: true}
    end

    assert Backend.supports?(ListCaps, nil, :range_read)
    assert Backend.supports?(SetCaps, nil, :range_read)
    refute Backend.supports?(MapCaps, nil, :range_read)
  end

  test "memory and filesystem backends serve ranges" do
    {:ok, storage} = Storage.init(%{storage_type: :memory})
    :ok = Storage.write_chunk(storage, {0}, <<0, 1, 2, 3, 4, 5, 6, 7, 8, 9>>)
    assert Storage.supports?(storage, :range_read)
    assert {:ok, <<3, 4, 5>>} = Storage.read_chunk_range(storage, {0}, 3, 3)
    assert {:ok, %{size: 10}} = Storage.chunk_info(storage, {0})

    path = Path.join(System.tmp_dir!(), "ex_zarr_range_#{System.unique_integer([:positive])}")
    File.mkdir_p!(path)
    on_exit(fn -> File.rm_rf!(path) end)

    {:ok, fs} = Storage.init(%{storage_type: :filesystem, path: path})
    data = for(i <- 0..99, into: <<>>, do: <<i>>)
    :ok = Storage.write_chunk(fs, {0}, data)
    assert {:ok, slice} = Storage.read_chunk_range(fs, {0}, 10, 5)
    assert slice == binary_part(data, 10, 5)
    assert {:error, {:invalid_chunk_range, _}} = Storage.read_chunk_range(fs, {0}, 98, 5)
  end

  defp restore_env(key, nil), do: Application.delete_env(:ex_zarr, key)
  defp restore_env(key, value), do: Application.put_env(:ex_zarr, key, value)
end
