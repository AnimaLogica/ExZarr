defmodule ExZarr.MixProject do
  use Mix.Project

  @version "1.3.0"
  @source_url "https://github.com/AnimaLogica/ExZarr"

  def project do
    [
      app: :ex_zarr,
      version: @version,
      elixir: "~> 1.17",
      start_permanent: Mix.env() == :prod,
      deps: deps(),
      compilers: Mix.compilers(),
      aliases: aliases(),

      # Package info
      description: description(),
      package: package(),
      docs: docs(),
      name: "ExZarr",
      source_url: @source_url,

      # Testing
      test_coverage: [tool: ExCoveralls],

      # Dialyzer
      dialyzer: [
        plt_file: {:no_warn, "priv/plts/dialyzer.plt"},
        plt_add_apps: [:mix, :ex_unit],
        flags: [:underspecs, :unmatched_returns],
        ignore_warnings: ".dialyzer_ignore.exs"
      ]
    ]
  end

  defp aliases do
    [
      verify: &verify/1
    ]
  end

  def application do
    [
      mod: {ExZarr.Application, []},
      extra_applications: [:logger, :crypto, :mnesia]
    ]
  end

  def cli do
    [
      preferred_envs: [
        coveralls: :test,
        "coveralls.detail": :test,
        "coveralls.post": :test,
        "coveralls.html": :test,
        "coveralls.github": :test,
        "coveralls.cobertura": :test
      ]
    ]
  end

  defp deps do
    [
      # JSON encoding/decoding for metadata
      {:jason, "~> 1.4"},

      # Compression codecs (zstd, lz4, snappy, bzip2, blosc, crc32c): pure-Rust
      # NIFs with precompiled binaries, so no system libraries or toolchains.
      {:ex_codecs, "~> 0.2.4"},

      # Cloud storage backends (optional)
      {:ex_aws, "~> 2.5", optional: true},
      {:ex_aws_s3, "~> 2.5", optional: true},
      {:sweet_xml, "~> 0.7", optional: true},
      {:goth, "~> 1.4", optional: true},
      {:azure_sdk, "~> 0.4.1", optional: true},
      # >= 0.6.1 for CVE-2026-49755 (azure_sdk and ex_aws both allow 0.6)
      {:req, "~> 0.6.1", optional: true},

      # Database storage backends (optional)
      {:mongodb_driver, "~> 1.4", optional: true},

      # Observability
      {:telemetry, "~> 1.2"},

      # Numerical computing (optional)
      {:nx, "~> 0.7", optional: true},

      # Streaming pipelines (optional)
      {:flow, "~> 1.2", optional: true},
      {:gen_stage, "~> 1.2", optional: true},
      {:broadway, "~> 1.0", optional: true},
      {:ex_doc, "~> 0.39", only: :dev, runtime: false},
      {:credo, "~> 1.7", only: [:dev, :test], runtime: false},
      {:ex_slop, "~> 0.4.5", only: [:dev, :test], runtime: false},
      {:doctor, "~> 0.23.0", only: :dev, runtime: false},
      {:dialyxir, "~> 1.4", only: [:dev, :test], runtime: false},
      {:excoveralls, "~> 0.18", only: :test},
      {:stream_data, "~> 1.1", only: [:dev, :test]},
      {:mox, "~> 1.1", only: :test},
      {:benchee, "~> 1.3", only: :dev},
      {:sobelow, "~> 0.14", only: [:dev, :test], runtime: false, warn_if_outdated: true}
    ]
  end

  defp description do
    """
    Pure Elixir implementation of Zarr v2 and v3: compressed, chunked, N-dimensional arrays
    with full Python zarr-python compatibility. Supports chunk streaming, custom encoders,
    and multiple storage backends including S3 and GCS.
    """
  end

  defp package do
    [
      name: "ex_zarr",
      licenses: ["MIT"],
      links: %{
        "GitHub" => @source_url,
        "Changelog" => "#{@source_url}/blob/main/CHANGELOG.md",
        "Zarr Specification" => "https://zarr.dev"
      },
      maintainers: ["Thanos Vassilakis"],
      files: [
        "lib",
        ".formatter.exs",
        "mix.exs",
        "README.md",
        "CHANGELOG.md",
        "docs/INTEROPERABILITY.md",
        "LICENSE"
      ]
    ]
  end

  defp docs do
    [
      main: "what_is_zarr",
      extras: [
        # Getting Started
        "docs/guides/what_is_zarr.md",
        {"README.md", title: "Introduction"},

        # Core Concepts
        "docs/guides/core_concepts.md",
        "docs/guides/parallel_io.md",

        # Storage and Backends
        "docs/guides/storage_providers.md",
        "docs/guides/custom_storage_backend.md",

        # Compression and Data Processing
        "docs/guides/compression_codecs.md",
        "docs/guides/python_interop.md",

        # Advanced Topics
        "docs/guides/performance.md",
        "docs/guides/nx_integration.md",
        "docs/guides/telemetry.md",
        "docs/educational/v1_1_streaming_guide.md",

        # Examples
        "docs/livebooks/README.md",
        "docs/livebooks/01_core_zarr/01_01_first_zarr_array.livemd",
        "docs/livebooks/01_core_zarr/01_02_metadata_and_chunks.livemd",
        "docs/livebooks/01_core_zarr/01_03_chunk_streaming.livemd",
        "docs/livebooks/03_nx_ml/03_01_zarr_to_nx.livemd",
        "docs/livebooks/03_nx_ml/03_02_streaming_minibatches.livemd",
        "docs/livebooks/03_nx_ml/03_03_training_from_zarr.livemd",
        "docs/livebooks/01_core_zarr/01_04_codecs_and_pipelines.livemd",
        "docs/livebooks/04_ai_genai/04_01_embeddings_in_zarr.livemd",
        "docs/livebooks/05_finance/05_01_tick_data_cube.livemd",
        "docs/livebooks/broadway_pipeline.livemd",
        "docs/livebooks/nx_streaming.livemd",
        "docs/livebooks/zarr_fundamentals.livemd",
        "docs/livebooks/earthmover_datacube.livemd",
        "docs/livebooks/xarray_zarr_intro.livemd",
        "docs/livebooks/benchmarking_zarr.livemd",
        "examples/README.md",

        # Cookbooks
        "docs/livebooks/06_cookbook/06_01_100gb_arrays.livemd",
        "docs/livebooks/06_cookbook/06_02_1tb_arrays.livemd",
        "docs/livebooks/06_cookbook/06_03_image_archives.livemd",
        "docs/livebooks/06_cookbook/06_04_ml_pipelines.livemd",
        "docs/livebooks/06_cookbook/06_05_geospatial.livemd",
        "docs/livebooks/06_cookbook/06_06_scientific_computing.livemd",
        "docs/livebooks/06_cookbook/06_07_distributed.livemd",

        # Architecture
        "docs/architecture_review.md",
        "docs/gap_analysis.md",
        "docs/v1_1_design.md",
        "docs/cloud_storage_patterns.md",

        # Additional Documentation
        "CHANGELOG.md",
        "docs/release_notes_v1_1_0.md",
        "docs/release_notes_v1_2_0.md",
        "docs/release_notes_v1_3_0.md",
        "docs/ROADMAP.md",
        "docs/ZARR_V3_STATUS.md",
        "docs/INTEROPERABILITY.md",
        "docs/SECURITY.md",
        "docs/PERFORMANCE_IMPROVEMENTS.md",
        "docs/V2_TO_V3_MIGRATION.md",
        "docs/migration_guide_v1_1_0.md",
        "benchmarks/README.md",
        "LICENSE",

        # Reference
        "docs/guides/troubleshooting.md",
        "docs/guides/glossary.md",

        # Contributing
        "docs/guides/contributing.md"
      ],
      groups_for_extras: [
        "Getting Started": [
          "docs/guides/what_is_zarr.md",
          "README.md"
        ],
        "Core Concepts": [
          "docs/guides/core_concepts.md",
          "docs/guides/parallel_io.md"
        ],
        "Storage and Backends": [
          "docs/guides/storage_providers.md",
          "docs/guides/custom_storage_backend.md"
        ],
        "Compression and Data Processing": [
          "docs/guides/compression_codecs.md",
          "docs/guides/python_interop.md"
        ],
        "Advanced Topics": [
          "docs/guides/performance.md",
          "docs/guides/nx_integration.md",
          "docs/guides/telemetry.md",
          "docs/educational/v1_1_streaming_guide.md"
        ],
        Examples: [
          "docs/livebooks/README.md",
          "docs/livebooks/01_core_zarr/01_01_first_zarr_array.livemd",
          "docs/livebooks/01_core_zarr/01_02_metadata_and_chunks.livemd",
          "docs/livebooks/01_core_zarr/01_03_chunk_streaming.livemd",
          "docs/livebooks/03_nx_ml/03_01_zarr_to_nx.livemd",
          "docs/livebooks/03_nx_ml/03_02_streaming_minibatches.livemd",
          "docs/livebooks/03_nx_ml/03_03_training_from_zarr.livemd",
          "docs/livebooks/01_core_zarr/01_04_codecs_and_pipelines.livemd",
          "docs/livebooks/04_ai_genai/04_01_embeddings_in_zarr.livemd",
          "docs/livebooks/05_finance/05_01_tick_data_cube.livemd",
          "docs/livebooks/broadway_pipeline.livemd",
          "docs/livebooks/nx_streaming.livemd",
          "docs/livebooks/zarr_fundamentals.livemd",
          "docs/livebooks/earthmover_datacube.livemd",
          "docs/livebooks/xarray_zarr_intro.livemd",
          "docs/livebooks/benchmarking_zarr.livemd",
          "examples/README.md"
        ],
        Cookbooks: [
          "docs/livebooks/06_cookbook/06_01_100gb_arrays.livemd",
          "docs/livebooks/06_cookbook/06_02_1tb_arrays.livemd",
          "docs/livebooks/06_cookbook/06_03_image_archives.livemd",
          "docs/livebooks/06_cookbook/06_04_ml_pipelines.livemd",
          "docs/livebooks/06_cookbook/06_05_geospatial.livemd",
          "docs/livebooks/06_cookbook/06_06_scientific_computing.livemd",
          "docs/livebooks/06_cookbook/06_07_distributed.livemd"
        ],
        Architecture: [
          "docs/architecture_review.md",
          "docs/gap_analysis.md",
          "docs/v1_1_design.md",
          "docs/cloud_storage_patterns.md"
        ],
        "Additional Documentation": [
          "CHANGELOG.md",
          "docs/ROADMAP.md",
          "docs/ZARR_V3_STATUS.md",
          "docs/INTEROPERABILITY.md",
          "docs/SECURITY.md",
          "docs/PERFORMANCE_IMPROVEMENTS.md",
          "docs/V2_TO_V3_MIGRATION.md",
          "benchmarks/README.md",
          "LICENSE"
        ],
        "Release Notes & Migration Guides": [
          "docs/release_notes_v1_1_0.md",
          "docs/release_notes_v1_2_0.md",
          "docs/release_notes_v1_3_0.md",
          "docs/migration_guide_v1_1_0.md"
        ],
        Reference: [
          "docs/guides/troubleshooting.md",
          "docs/guides/glossary.md"
        ],
        Contributing: [
          "docs/guides/contributing.md"
        ]
      ],
      source_ref: "v#{@version}",
      source_url: @source_url,
      authors: ["Thanos Vassilakis"],
      logo: nil,
      api_reference: true,
      formatters: ["html"],
      before_closing_body_tag: &before_closing_body_tag/1
    ]
  end

  # Add search and navigation enhancements
  defp before_closing_body_tag(:html) do
    """
    <script>
      // Add keyboard shortcuts for documentation navigation
      document.addEventListener('keydown', function(e) {
        // Press 'g' then 'h' to go to guides home
        if (e.key === 'g') {
          setTimeout(function() {
            document.addEventListener('keydown', function handler(e2) {
              if (e2.key === 'h') {
                window.location.href = 'what_is_zarr.html';
              }
              document.removeEventListener('keydown', handler);
            }, {once: true});
          }, 100);
        }
      });
    </script>
    """
  end

  defp before_closing_body_tag(_), do: ""

  defp verify(_) do
    steps = [
      {"compile --warnings-as-errors", :dev},
      {"format --check-formatted", :dev},
      {"credo --strict", :dev},
      {"doctor --full --raise", :dev},
      {"sobelow --config", :dev},
      {"dialyzer", :dev},
      {"test --cover", :test},
      {"docs --warnings-as-errors", :dev}
    ]

    Enum.each(steps, fn {task, env} ->
      Mix.shell().info([:bright, "==> mix #{task}", :reset])

      {_, exit_code} =
        System.cmd("mix", String.split(task),
          env: [{"MIX_ENV", to_string(env)}],
          into: IO.stream()
        )

      if exit_code != 0 do
        Mix.raise("mix #{task} failed (exit code #{exit_code})")
      end
    end)

    Mix.shell().info([:green, :bright, "\nAll verification checks passed!", :reset])
  end
end
