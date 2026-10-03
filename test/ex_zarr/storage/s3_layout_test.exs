defmodule ExZarr.Storage.S3LayoutTest do
  # Not async: replaces the global ExAws request module.
  use ExUnit.Case, async: false

  alias ExZarr.Array

  # Serves real ExAws.S3 operations from an ETS table, so the request shapes
  # (keys, Range and If-Match headers) are exactly what ExAws would send.
  defmodule EtsS3 do
    @table __MODULE__

    def reset do
      if :ets.whereis(@table) != :undefined, do: :ets.delete(@table)
      :ets.new(@table, [:named_table, :public, :set])
    end

    def keys, do: for({key, _} <- :ets.tab2list(@table), is_binary(key), do: key) |> Enum.sort()
    def ranged_gets, do: for({{:ranged, _}, range} <- :ets.tab2list(@table), do: range)
    def put(key, body), do: :ets.insert(@table, {key, body})

    def request(%{http_method: :put, path: key, body: body}, _config) do
      put(key, body)
      {:ok, %{status_code: 200}}
    end

    def request(%{http_method: :head, path: key}, _config) do
      case :ets.lookup(@table, key) do
        [{_, body}] ->
          {:ok,
           %{
             headers: [
               {"Content-Length", Integer.to_string(byte_size(body))},
               {"ETag", etag(body)}
             ]
           }}

        [] ->
          {:error, {:http_error, 404, "Not Found"}}
      end
    end

    def request(%{http_method: :get, path: "/", params: %{"prefix" => prefix}}, _config) do
      contents =
        for {key, _} <- :ets.tab2list(@table), String.starts_with?(key, prefix), do: %{key: key}

      {:ok, %{body: %{contents: contents}}}
    end

    def request(%{http_method: :get, path: key, headers: headers}, _config) do
      case :ets.lookup(@table, key) do
        [{_, body}] ->
          cond do
            headers["if-match"] && headers["if-match"] != etag(body) ->
              {:error, {:http_error, 412, "Precondition Failed"}}

            range = headers["range"] ->
              :ets.insert(@table, {{:ranged, make_ref()}, range})

              [first, last] =
                range
                |> String.trim_leading("bytes=")
                |> String.split("-")
                |> Enum.map(&String.to_integer/1)

              {:ok, %{body: binary_part(body, first, last - first + 1)}}

            true ->
              {:ok, %{body: body}}
          end

        [] ->
          {:error, {:http_error, 404, "Not Found"}}
      end
    end

    def request(%{http_method: :delete, path: key}, _config) do
      :ets.delete(@table, key)
      {:ok, %{status_code: 204}}
    end

    defp etag(body), do: ~s("#{:erlang.phash2(body)}")
  end

  setup do
    EtsS3.reset()
    previous = Application.get_env(:ex_zarr, :ex_aws_module)
    Application.put_env(:ex_zarr, :ex_aws_module, EtsS3)
    ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)

    on_exit(fn ->
      if previous,
        do: Application.put_env(:ex_zarr, :ex_aws_module, previous),
        else: Application.delete_env(:ex_zarr, :ex_aws_module)
    end)

    :ok
  end

  defp s3_opts(extra), do: [storage: :s3, bucket: "bucket", prefix: "arrays/a"] ++ extra

  test "zarr_version: 3 writes zarr.json and c/ chunk keys" do
    {:ok, array} =
      ExZarr.create(s3_opts(shape: {4, 4}, chunks: {2, 2}, dtype: :int32, zarr_version: 3))

    :ok = Array.save(array, [])
    data = for i <- 0..15, into: <<>>, do: <<i::signed-little-32>>
    :ok = Array.set_slice(array, data, start: {0, 0}, stop: {4, 4})

    assert EtsS3.keys() ==
             [
               "arrays/a/c/0/0",
               "arrays/a/c/0/1",
               "arrays/a/c/1/0",
               "arrays/a/c/1/1",
               "arrays/a/zarr.json"
             ]

    assert {:ok, chunks} = ExZarr.Storage.list_chunks(array.storage)
    assert Enum.sort(chunks) == [{0, 0}, {0, 1}, {1, 0}, {1, 1}]

    # Reopen without saying which version: the backend finds zarr.json.
    {:ok, reopened} = ExZarr.open(s3_opts([]))
    assert reopened.version == 3
    assert {:ok, ^data} = Array.get_slice(reopened, start: {0, 0}, stop: {4, 4})
  end

  test "v2 arrays keep .zarray and dotted keys" do
    {:ok, array} = ExZarr.create(s3_opts(shape: {4}, chunks: {2}, dtype: :int32))
    :ok = Array.save(array, [])
    :ok = Array.set_slice(array, <<1::little-32, 2::little-32>>, start: {0}, stop: {2})

    assert EtsS3.keys() == ["arrays/a/.zarray", "arrays/a/0"]
    {:ok, reopened} = ExZarr.open(s3_opts([]))
    assert reopened.version == 2
  end

  test "sharded reads use real Range requests" do
    {:ok, array} =
      ExZarr.create(
        s3_opts(
          shape: {8, 8},
          chunks: {2, 2},
          shard_shape: {2, 2},
          dtype: :int32,
          zarr_version: 3
        )
      )

    :ok = Array.save(array, [])
    data = for i <- 0..63, into: <<>>, do: <<i::signed-little-32>>
    :ok = Array.set_slice(array, data, start: {0, 0}, stop: {8, 8})

    test_pid = self()
    handler = "s3-layout-#{System.unique_integer([:positive])}"

    :telemetry.attach(
      handler,
      [:ex_zarr, :shard, :range_read],
      fn _, m, md, _ -> send(test_pid, {:shard_read, m, md}) end,
      nil
    )

    on_exit(fn -> :telemetry.detach(handler) end)

    {:ok, reopened} = ExZarr.open(s3_opts([]))
    assert {:ok, region} = Array.get_slice(reopened, start: {2, 2}, stop: {4, 4})
    assert region == <<18::little-32, 19::little-32, 26::little-32, 27::little-32>>

    assert_receive {:shard_read, %{range_count: 2}, %{fallback: false}}
    # The Range header reached S3 (ExAws drops unknown options such as `headers:`).
    assert length(EtsS3.ranged_gets()) == 2
  end
end
