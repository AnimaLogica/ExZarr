defmodule Mix.Tasks.Livebook.Test do
  use Mix.Task

  @shortdoc "Run .livemd notebooks as tests by executing their Elixir code fences"

  @moduledoc """
  Discovers .livemd files, extracts elixir fenced blocks, writes a temp .exs, and runs it.

  Cells are evaluated one at a time, in order, carrying variable bindings and
  the environment (aliases, imports, requires) forward, the way Livebook does.
  Code in later cells is compiled only after earlier cells ran, so a struct from
  a package installed by the setup cell's `Mix.install/2` can be used.

  By default the notebooks install `ex_zarr` from Hex, as a reader would. Pass
  `--local` to point `{:ex_zarr, "~> ..."}` at this checkout instead, so CI
  tests the notebooks against the code being changed.

  Why this exists:
  - No dependency on Livebook
  - CI-friendly
  - Catches broken cells / stale code in docs

  Usage:
    mix livebook.test
    mix livebook.test --paths "docs/livebooks/**/*.livemd" --paths "docs/**/*.livemd"
    mix livebook.test --pattern ExZarr --max 4 --timeout 300
    mix livebook.test --fail-on-warn
    mix livebook.test --skip-tag "livebook:test skip"
    mix livebook.test --local
  """

  @default_paths ["docs/livebooks/**/*.livemd", "docs/**/*.livemd"]
  @default_timeout_sec 300
  @default_max System.schedulers_online()

  @impl true
  def run(args) do
    # Note: We don't start the app here because livebooks use Mix.install
    # to create isolated environments with their own dependencies

    {opts, _rest, invalid} =
      OptionParser.parse(args,
        switches: [
          paths: :keep,
          pattern: :string,
          max: :integer,
          timeout: :integer,
          fail_on_warn: :boolean,
          skip_tag: :string,
          local: :boolean
        ],
        aliases: [p: :paths]
      )

    if invalid != [] do
      Mix.raise("Invalid options: #{inspect(invalid)}")
    end

    patterns =
      case Keyword.get_values(opts, :paths) do
        [] -> @default_paths
        ps -> ps
      end

    filter_pattern = Keyword.get(opts, :pattern)
    max_conc = Keyword.get(opts, :max, @default_max)
    timeout_sec = Keyword.get(opts, :timeout, @default_timeout_sec)
    fail_on_warn? = Keyword.get(opts, :fail_on_warn, false)
    skip_tag = Keyword.get(opts, :skip_tag, "livebook:test skip")
    local? = Keyword.get(opts, :local, false)

    files =
      patterns
      |> Enum.flat_map(&Path.wildcard/1)
      |> Enum.uniq()
      |> Enum.sort()
      |> maybe_filter(filter_pattern)

    if files == [] do
      Mix.shell().info("No .livemd files found (patterns: #{Enum.join(patterns, ", ")})")
      System.halt(0)
    end

    Mix.shell().info(
      "Running #{length(files)} livebook(s) with max_concurrency=#{max_conc} timeout=#{timeout_sec}s"
    )

    results =
      files
      |> Task.async_stream(
        fn path -> run_one(path, timeout_sec, fail_on_warn?, skip_tag, local?) end,
        max_concurrency: max_conc,
        timeout: (timeout_sec + 30) * 1_000,
        ordered: true
      )
      |> Enum.map(fn
        {:ok, res} ->
          res

        {:exit, reason} ->
          {:error, %{path: "unknown", status: :task_exit, output: inspect(reason)}}
      end)

    Enum.each(results, &print_result/1)

    failures = Enum.filter(results, &match?({:error, _}, &1))

    if failures != [] do
      Mix.raise("#{length(failures)}/#{length(results)} livebook(s) failed")
    end
  end

  defp maybe_filter(files, nil), do: files
  defp maybe_filter(files, pat), do: Enum.filter(files, &String.contains?(&1, pat))

  defp run_one(path, _timeout_sec, fail_on_warn?, skip_tag, local?) do
    livemd = File.read!(path)

    if skip_entire_notebook?(livemd, skip_tag) do
      {:ok, %{path: path, skipped: true}}
    else
      script = __MODULE__.LivemdExtract.to_elixir_script(livemd, local: local?)

      if blank?(script) do
        {:error,
         %{path: path, status: :no_elixir_blocks, output: "No ```elixir code fences found"}}
      else
        tmp = tmp_script_path(path)
        File.write!(tmp, script)

        {output, status} =
          System.cmd("elixir", [tmp],
            env: child_env(),
            stderr_to_stdout: true,
            into: ""
          )

        cond do
          status == 0 and fail_on_warn? and has_warning?(output) ->
            {:error, %{path: path, status: :warnings, output: output}}

          status == 0 ->
            {:ok, %{path: path, skipped: false}}

          true ->
            {:error, %{path: path, status: status, output: output}}
        end
      end
    end
  rescue
    e ->
      {:error,
       %{path: path, status: :exception, output: Exception.format(:error, e, __STACKTRACE__)}}
  end

  defp print_result({:ok, %{path: path, skipped: true}}),
    do: Mix.shell().info("⏭️  SKIP  #{path}")

  defp print_result({:ok, %{path: path}}),
    do: Mix.shell().info("✅ PASS  #{path}")

  defp print_result({:error, %{path: path, status: status, output: out}}) do
    Mix.shell().error("❌ FAIL  #{path} (#{inspect(status)})\n#{truncate(out)}\n")
  end

  # Keeps the end of the output, where the failing cell and error are.
  defp truncate(s) when is_binary(s) do
    max = 12_000

    if byte_size(s) > max,
      do: "…(truncated)\n" <> binary_part(s, byte_size(s) - max, max),
      else: s
  end

  defp tmp_script_path(path) do
    hash = :erlang.phash2(path)
    Path.join(System.tmp_dir!(), "livemd_test_#{hash}.exs")
  end

  defp child_env do
    # Provide MIX_ENV and preserve current environment
    [{"MIX_ENV", to_string(Mix.env())} | System.get_env() |> Enum.to_list()]
  end

  defp has_warning?(output) do
    # Simple heuristic: adjust if you want stricter matching
    String.contains?(output, "warning:")
  end

  defp blank?(s), do: String.trim(s) == ""

  defp skip_entire_notebook?(livemd, tag) when is_binary(tag) do
    # Convention: if a notebook contains this marker anywhere, skip the whole thing
    # Example in the .livemd:
    #   <!-- livebook:test skip -->
    String.contains?(livemd, "<!-- #{tag} -->") or String.contains?(livemd, "# #{tag}")
  end

  defmodule LivemdExtract do
    @moduledoc false

    # Matches:
    # ```elixir
    # code...
    # ```
    @elixir_fence ~r/```elixir\s*\n(.*?)```/ms

    def to_elixir_script(livemd, opts \\ []) when is_binary(livemd) do
      cells =
        @elixir_fence
        |> Regex.scan(livemd, capture: :all_but_first)
        |> List.flatten()
        |> Enum.map(&String.trim_trailing/1)
        |> Enum.reject(&(String.trim(&1) == ""))
        |> Enum.map(&rewrite_paths(&1, Keyword.get(opts, :local, false)))

      if cells == [], do: "", else: runner_script(cells)
    end

    # Each cell is quoted and evaluated with the binding and env left by the
    # previous cell, so later cells compile after earlier ones ran.
    defp runner_script(cells) do
      """
      # Generated from .livemd by mix livebook.test
      # NOTE: Only ```elixir fenced blocks are executed, one cell at a time.
      cells = #{inspect(cells, limit: :infinity, printable_limit: :infinity)}

      cells
      |> Enum.with_index(1)
      |> Enum.reduce({[], Code.env_for_eval([])}, fn {code, index}, {binding, env} ->
        try do
          quoted = Code.string_to_quoted!(code, file: "cell \#{index}")
          {_value, binding, env} = Code.eval_quoted_with_env(quoted, binding, env)
          {binding, env}
        rescue
          error ->
            IO.puts("livebook cell \#{index} failed:")
            reraise error, __STACKTRACE__
        end
      end)
      """
    end

    defp rewrite_paths(code, local?) do
      project_root = File.cwd!()

      code =
        code
        |> String.replace(
          ~r/path: Path\.join\(__DIR__, "\.\.\/\.\.\/\.\."\)/,
          "path: \"#{project_root}\""
        )
        |> String.replace(
          ~r/path: Path\.join\(__DIR__, "\.\.\/\.\."\)/,
          "path: \"#{project_root}\""
        )
        |> String.replace(~r/path: Path\.join\(__DIR__, "\.\."\)/, "path: \"#{project_root}\"")
        |> String.replace(~r/path: Path\.dirname\(__DIR__\)/, "path: \"#{project_root}\"")

      if local? do
        String.replace(
          code,
          ~r/^(\s*)\{:ex_zarr, "~> [^"]+"\}/m,
          "\\1{:ex_zarr, path: \"#{project_root}\"}"
        )
      else
        code
      end
    end
  end
end
