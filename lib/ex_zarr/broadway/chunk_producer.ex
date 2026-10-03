if Code.ensure_loaded?(Broadway) do
  defmodule ExZarr.Broadway.ChunkProducer do
    @moduledoc """
    Finite Broadway producer that streams Zarr chunks as messages.

    Each message has `data: {chunk_index, binary}`. When every chunk has been
    emitted the producer stops with `:normal`, which shuts down the Broadway
    topology.

    Used via `ExZarr.Broadway.chunk_pipeline_options/3` or as:

        producer: [
          module: {ExZarr.Broadway.ChunkProducer, array: array, stream_opts: []},
          concurrency: 1
        ]

    See `docs/livebooks/broadway_pipeline.livemd` for a Livebook example
    (trap exits when linking from an evaluation process).
    """

    use GenStage

    alias ExZarr.Streaming.Producer

    @doc """
    Starts the chunk producer.

    ## Options

      * `:array` - required `ExZarr.Array`
      * `:stream_opts` - options forwarded to chunk streaming (default `[]`)
    """
    def start_link(opts) do
      GenStage.start_link(__MODULE__, opts)
    end

    @impl GenStage
    def init(opts) do
      array = Keyword.fetch!(opts, :array)
      stream_opts = Keyword.get(opts, :stream_opts, [])

      {:producer, Producer.chunk_init(array, stream_opts)}
    end

    @impl GenStage
    def handle_demand(_demand, %{remaining: []} = state) do
      {:stop, :normal, state}
    end

    def handle_demand(demand, state) when demand > 0 do
      {events, new_state} = Producer.chunk_demand(demand, state)

      messages =
        Enum.map(events, fn
          {index, data} -> chunk_message({index, data})
          %{index: index, data: data} -> chunk_message({index, data})
        end)

      {:noreply, messages, new_state}
    end

    defp chunk_message(data) do
      %Broadway.Message{
        data: data,
        acknowledger: Broadway.NoopAcknowledger.init()
      }
    end
  end
else
  defmodule ExZarr.Broadway.ChunkProducer do
    @moduledoc """
    Finite Broadway producer that streams Zarr chunks as messages.

    Broadway is an optional dependency. Add `{:broadway, "~> 1.0"}` to your deps.
    """

    @doc """
    Starts the chunk producer. Requires Broadway to be available.
    """
    def start_link(_opts) do
      {:error,
       %ArgumentError{
         message: "Broadway is required. Add {:broadway, \"~> 1.0\"} to your deps."
       }}
    end
  end
end
