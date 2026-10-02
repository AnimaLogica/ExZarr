# Telemetry Guide

ExZarr v1.1+ emits `:telemetry` events for streaming and chunk I/O.

## Events

Chunk read and write use `:telemetry.span/3`. Attach to the `:stop` events for
duration measurements. Stream start/stop use `:telemetry.execute/3`.

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:ex_zarr, :chunk, :read, :stop]` | `%{duration: native_time}` | `%{array: ref, chunk_index: tuple}` |
| `[:ex_zarr, :chunk, :write, :stop]` | `%{duration: native_time, bytes: integer}` | `%{array: ref, chunk_index: tuple}` |
| `[:ex_zarr, :stream, :start]` | `%{}` | `%{array: ref, type: atom, opts: keyword}` |
| `[:ex_zarr, :stream, :stop]` | `%{duration: native_time, count: integer}` | `%{array: ref, type: atom}` |
| `[:ex_zarr, :shard, :range_read]` | `%{bytes_requested, bytes_fetched, range_count}` | `%{fallback: boolean, fallback_reason: term}` |

`ExZarr.Telemetry.events/0` returns all attachable event names, including
`:start` and `:exception` variants for chunk spans.

`[:ex_zarr, :shard, :range_read]` fires once per shard read of a sharded v3
array. On the range path `bytes_requested` is the encoded size of the inner
chunks asked for, `bytes_fetched` adds the shard index, and `range_count`
counts the range requests (index + inner chunks). When the whole shard is
downloaded instead, `fallback` is true, `fallback_reason` says why (for example
`:no_range_support`, or the range error), both byte counts are the shard size,
and `range_count` is 1.

Range reads are tuned with two application settings:

```elixir
config :ex_zarr,
  range_read_concurrency: 4,   # parallel inner-chunk range requests per shard
  range_read_timeout: 60_000   # per-request timeout in ms
```

## Installation

```elixir
defmodule MyApp.Application do
  use Application

  def start(_type, _args) do
    :telemetry.attach(
      "ex-zarr-chunk-reads",
      [:ex_zarr, :chunk, :read, :stop],
      fn _event, measurements, metadata, _config ->
        IO.inspect({measurements.duration, metadata.chunk_index})
      end,
      nil
    )

    Supervisor.start_link([], strategy: :one_for_one)
  end
end
```

## Stream Monitoring

```elixir
:telemetry.attach(
  "ex-zarr-stream-stop",
  [:ex_zarr, :stream, :stop],
  fn _event, %{duration: duration, count: count}, %{type: type}, _config ->
    IO.inspect({type, count, duration})
  end,
  nil
)

array
|> ExZarr.Array.stream_chunks(concurrency: 4)
|> Enum.to_list()
```

## Notes

- `array` metadata is a tuple `{shape, chunks, dtype}`, not the full struct.
- Stream `:type` is `:chunks`, `:slices`, or `:write`.
- Chunk span `:exception` events include metadata but no duration measurement.
