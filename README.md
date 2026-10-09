# ExZarr


[![Hex version](https://img.shields.io/hexpm/v/ex_zarr.svg)](https://hex.pm/packages/ex_zarr)
[![Hex docs](https://img.shields.io/badge/docs-hexdocs.pm-blue)](https://hexdocs.pm/ex_zarr)
[![License](https://img.shields.io/badge/License-MIT-blue.svg)](https://github.com/AnimaLogica/ExZarr/blob/main/LICENSE)
[![CI](https://github.com/AnimaLogica/ExZarr/actions/workflows/ci.yml/badge.svg)](https://github.com/AnimaLogica/ExZarr/actions/workflows/ci.yml)
[![Coverage Status](https://coveralls.io/repos/github/AnimaLogica/ExZarr/badge.svg?branch=main)](https://coveralls.io/github/AnimaLogica/ExZarr?branch=main)


Elixir implementation of [Zarr](https://zarr.dev): compressed, chunked, N-dimensional arrays designed for parallel computing and scientific data storage.

**Zarr v3.1 core support:** ExZarr implements Zarr v2 and Zarr core v3.1 for the
documented dtype/codec subset, with automatic version detection and Python
interop tested in CI against zarr-python 2.18 / 3.2 / 3.3 / 3.4. See
[ZARR_V3_STATUS.md](docs/ZARR_V3_STATUS.md) for details and known limitations.

## Features

- **Zarr v3 and v2 Support** - Full implementation of both specifications with automatic version detection
- **High Performance** - 26x faster multi-chunk reads with near-optimal scaling (see [Performance Guide](docs/guides/performance.md))
- **N-dimensional arrays** with support for 10 data types (int8-64, uint8-64, float32/64)
- **BEAM-native streaming** - `stream_chunks/2`, `stream_slices/3`, and `write_stream/3` for bounded-memory processing
- **Nx** - `ExZarr.Nx` converts arrays and chunks to tensors; `ExZarr.Nx.DataLoader` streams sample-axis batches for training. Nx is optional. See [Using Nx](docs/guides/getting_started.md#using-nx)
- **Telemetry** - `:telemetry` events for chunk I/O and stream lifecycle (`ExZarr.Telemetry`)
- **Pipeline integrations** - Optional Flow, GenStage, and Broadway support for production pipelines
- **Parallel chunk processing** - Automatic parallel I/O and decompression for large operations
- **Chunking** along arbitrary dimensions for optimized I/O operations
- **Compression** - Erlang `:zlib` plus [ExCodecs](https://hex.pm/packages/ex_codecs) codecs (zstd, lz4, snappy, blosc, bzip2, crc32c), precompiled for macOS, Linux and Windows
- **Flexible storage** backends (in-memory, filesystem, and zip archive)
- **Custom storage backends** with plugin architecture for S3, databases, and more
- **Hierarchical groups** for organizing multiple arrays
- **Full Python interoperability** - Read and write arrays compatible with zarr-python 2.x and 3.x
- **Property-based testing** with comprehensive test coverage

## Installation

Add `ex_zarr` to your list of dependencies in `mix.exs`:

```elixir
def deps do
  [
    {:ex_zarr, "~> 1.3"}
  ]
end
```

## Quick Start

### Creating an Array

```elixir
# Create a Zarr v3 array (recommended for new projects)
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},
    %{name: "gzip", configuration: %{level: 5}}
  ],
  zarr_version: 3,
  storage: :memory
)

# Or use v2 format for compatibility with older tools
{:ok, array_v2} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  compressor: :zlib,
  zarr_version: 2,
  storage: :memory
)
```

### Saving and Loading Arrays

```elixir
# Save array to filesystem
:ok = ExZarr.save(array, path: "/tmp/my_array")

# Open existing array
{:ok, array} = ExZarr.open(path: "/tmp/my_array")

# Load entire array into memory
{:ok, data} = ExZarr.load(path: "/tmp/my_array")
```

### Streaming Large Arrays (v1.1+)

Process arrays larger than memory with lazy chunk streaming:

```elixir
{:ok, array} = ExZarr.open(path: "/data/large_dataset")

array
|> ExZarr.Array.stream_chunks(concurrency: 8, ordered: false)
|> Stream.map(fn {_index, data} -> process_chunk(data) end)
|> Stream.run()

# Row-wise slice streaming
array
|> ExZarr.Array.stream_slices(0, start: {0, 0}, stop: {100, 10})
|> Enum.each(fn {_start, row} -> process_row(row) end)
```

Attach telemetry handlers for production observability - see [docs/guides/telemetry.md](docs/guides/telemetry.md).

```elixir
ExZarr.Array.write_stream(array, chunk_stream,
  batch_size: 4,
  checkpoint: fn stats -> save_progress(stats) end
)
```

See [migration_guide_v1_1_0.md](docs/migration_guide_v1_1_0.md) and [docs/educational/v1_1_streaming_guide.md](docs/educational/v1_1_streaming_guide.md).

## Performance

ExZarr v0.8+ includes major performance optimizations:

- **26x faster multi-chunk reads** - Optimized from 110ms to 4.2ms for 16-chunk operations
- **Near-optimal scaling** - Reading N chunks takes ~N× single chunk time
- **Parallel I/O** - Automatic parallelization for multi-chunk operations
- **99% memory reduction** - Eliminated redundant binary copies

**Benchmark results** (400×400 array, 16 chunks):

- Before: 110ms per read
- After: 4.2ms per read
- **Speedup: 26×**

See [Performance Guide](docs/guides/performance.md) for tuning recommendations and [Benchmarks](benchmarks/README.md) for running your own tests.

```bash
# Run quick performance check (completes in 6 seconds)
mix run benchmarks/slicing_bench_quick.exs
```

## Zarr Format Support

ExZarr provides production-ready support for both Zarr v2 and v3 specifications. Arrays can be created in either format, and opening arrays automatically detects the version.

### Zarr v3 - Fully Supported (Recommended for New Projects)

Zarr v3 is fully implemented with a unified codec pipeline and improved metadata format:

```elixir
# Create v3 array with unified codec pipeline
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  codecs: [
    %{name: "bytes"},  # Required array-to-bytes codec
    %{name: "gzip", configuration: %{level: 5}}  # Optional compression
  ],
  zarr_version: 3,
  storage: :filesystem,
  path: "/tmp/my_v3_array"
)
```

### Zarr v2 (Default for Compatibility)

Zarr v2 uses separate filters and compressor configuration:

```elixir
# Create v2 array (explicit version)
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 2,
  storage: :filesystem,
  path: "/tmp/my_v2_array"
)
```

### Automatic Version Detection

When opening arrays, ExZarr automatically detects the format version:

```elixir
# Opens v2 or v3 transparently
{:ok, array} = ExZarr.open(path: "/tmp/my_array")

# Check which version was detected
array.version  # Returns 2 or 3
```

### Key Differences Between v2 and v3


| Feature            | v2                                  | v3                                      |
| ------------------ | ----------------------------------- | --------------------------------------- |
| Metadata file      | `.zarray`                           | `zarr.json`                             |
| Chunk keys         | Dot-separated (`0.1.2`)             | Slash-separated with prefix (`c/0/1/2`) |
| Codec organization | Separate `filters` and `compressor` | Unified `codecs` array                  |
| Data types         | NumPy-style strings (`<f8`)         | Simplified names (`float64`)            |
| Groups             | Separate `.zgroup` files            | Unified `zarr.json` with `node_type`    |
| Attributes         | Separate `.zattrs` files            | Embedded in `zarr.json`                 |


### Converting from v2 to v3

v2-style configuration is automatically converted when creating v3 arrays:

```elixir
# This v2-style configuration
{:ok, array} = ExZarr.create(
  shape: {1000},
  chunks: {100},
  dtype: :int64,
  filters: [{:shuffle, [elementsize: 8]}],
  compressor: :zlib,
  zarr_version: 3  # Request v3 format
)

# Automatically converts to v3 codec pipeline:
# [
#   %{name: "shuffle", configuration: %{elementsize: 8}},
#   %{name: "bytes"},
#   %{name: "gzip", configuration: %{level: 5}}
# ]
```

For detailed migration guidance, see [docs/V2_TO_V3_MIGRATION.md](docs/V2_TO_V3_MIGRATION.md).

### Working with Groups

```elixir
# Create a hierarchical group structure
{:ok, root} = ExZarr.Group.create("/data",
  storage: :filesystem,
  path: "/tmp/zarr_data"
)

# Create arrays within the group
{:ok, measurements} = ExZarr.Group.create_array(root, "measurements",
  shape: {1000},
  chunks: {100},
  dtype: :float64
)

# Create subgroups
{:ok, subgroup} = ExZarr.Group.create_group(root, "experiments")
```

### Interoperability with Python

ExZarr is fully compatible with Python's zarr library. Arrays created by one can be read by the other:

```bash
# Run the interoperability demo
elixir examples/python_interop_demo.exs
```

This demonstrates:

- Creating arrays with ExZarr that Python can read
- Creating arrays with Python that ExZarr can read
- Compatible metadata and compression

**For detailed interoperability information, see [INTEROPERABILITY.md](docs/INTEROPERABILITY.md)** which covers:

- Data type compatibility table
- Compression compatibility guidelines
- Metadata format details
- File structure specifications
- Complete examples of multi-language workflows
- Troubleshooting common issues

### Custom Codecs Example

See how to create and use custom compression codecs:

```bash
# Run the custom codec example
mix run examples/custom_codec_example.exs
```

This demonstrates:

- Creating custom transformation codecs (UppercaseCodec)
- Creating custom compression codecs (RleCodec)
- Registering and unregistering codecs at runtime
- Querying codec information
- Chaining custom codecs with built-in codecs

### Custom Storage Backend Example

See the test suite for a complete example of implementing a custom storage backend:

```bash
# View the custom storage tests
cat test/ex_zarr_custom_storage_test.exs
```

The example demonstrates:

- Implementing the `ExZarr.Storage.Backend` behavior
- Registering and using custom backends
- Integration with filters and compression
- Registry operations (list, get, info)

## Supported Data Types

ExZarr supports the following data types:

- **Integers**: `:int8`, `:int16`, `:int32`, `:int64`
- **Unsigned integers**: `:uint8`, `:uint16`, `:uint32`, `:uint64`
- **Floating point**: `:float32`, `:float64`

All data types use little-endian byte order by default, consistent with the Zarr specification.

## Compression Codecs

ExZarr provides the following built-in compression options:

- **`:none`** - No compression (fastest, largest size)
- **`:zlib`** - Standard zlib compression (good balance of speed and compression)
- **`:crc32c`** - CRC32C checksum codec (Zarr v3 `crc32c`)
- **`:zstd`** - Zstandard compression
- **`:lz4`** - LZ4 compression (numcodecs `LZ4` format)
- **`:snappy`** - Snappy compression
- **`:blosc`** - Blosc meta-compressor (Blosc1 chunks, readable by numcodecs / zarr-python)
- **`:bzip2`** - Bzip2 compression (numcodecs `BZ2` format)

`:zlib` uses Erlang's built-in `:zlib` module. The other codecs come from
[ExCodecs](https://hex.pm/packages/ex_codecs), pure-Rust NIFs that are
downloaded precompiled for macOS, Linux (glibc and musl) and Windows, so no
system libraries or compilers are needed.

### Custom Codecs

ExZarr supports custom codecs through a behavior-based plugin system. You can create your own compression, checksum, or transformation codecs:

```elixir
defmodule MyCustomCodec do
  @behaviour ExZarr.Codecs.Codec

  @impl true
  def codec_id, do: :my_codec

  @impl true
  def codec_info do
    %{
      name: "My Custom Codec",
      version: "1.0.0",
      type: :compression,  # or :transformation
      description: "My custom compression algorithm"
    }
  end

  @impl true
  def available?, do: true

  @impl true
  def encode(data, opts) when is_binary(data) do
    # Your encoding logic here
    {:ok, compressed_data}
  end

  @impl true
  def decode(data, opts) when is_binary(data) do
    # Your decoding logic here
    {:ok, decompressed_data}
  end

  @impl true
  def validate_config(opts) do
    # Validate options
    :ok
  end
end

# Register your codec
:ok = ExZarr.Codecs.register_codec(MyCustomCodec)

# Use it like any built-in codec
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  compressor: :my_codec
)
```

For complete examples, see `examples/custom_codec_example.exs` which includes:

- `UppercaseCodec` - Simple transformation codec
- `RleCodec` - Run-length encoding compression

**Custom codec features:**

- Runtime registration and unregistration
- Behavior-based contract for consistency
- Seamless integration with built-in codecs
- Can be chained with other codecs
- Managed by supervised GenServer registry

## Storage Backends

ExZarr includes three built-in storage backends:

- **`:memory`** - In-memory storage for temporary arrays (non-persistent, fast)
- **`:filesystem`** - Local filesystem storage using Zarr v2 directory structure (persistent, interoperable)
- **`:zip`** - Zip archive storage for compact single-file arrays (portable, easy to distribute)

Arrays stored on the filesystem use the standard Zarr format:

- **v2 format**: Metadata in `.zarray` files, chunks as `0.0`, `0.1`, groups as `.zgroup`
- **v3 format**: Metadata in `zarr.json` files, chunks in `c/` directory as `c/0/0`, `c/0/1`
- Automatic format detection when opening existing arrays

### Using Zip Storage

Zip storage stores the entire array (metadata + all chunks) in a single zip file:

```elixir
# Create array with zip storage
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  dtype: :float64,
  storage: :zip,
  path: "/tmp/my_array.zip"
)

# Write data
ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {100, 100})

# Save to zip file
:ok = ExZarr.save(array, path: "/tmp/my_array.zip")

# Open existing zip
{:ok, reopened} = ExZarr.open(path: "/tmp/my_array.zip", storage: :zip)
```

### Custom Storage Backends

ExZarr supports custom storage backends through a behavior-based plugin system, similar to custom codecs. Create backends for S3, databases, cloud storage, or any other storage system:

```elixir
defmodule MyApp.S3Storage do
  @behaviour ExZarr.Storage.Backend

  @impl true
  def backend_id, do: :s3

  @impl true
  def init(config) do
    # Initialize S3 connection
    bucket = Keyword.fetch!(config, :bucket)
    {:ok, %{bucket: bucket, client: setup_s3_client()}}
  end

  @impl true
  def read_chunk(state, chunk_index) do
    # Read chunk from S3
    key = build_s3_key(chunk_index)
    AWS.S3.get_object(state.client, state.bucket, key)
  end

  @impl true
  def write_chunk(state, chunk_index, data) do
    # Write chunk to S3
    key = build_s3_key(chunk_index)
    AWS.S3.put_object(state.client, state.bucket, key, data)
  end

  # Implement other required callbacks...
end

# Register your backend
:ok = ExZarr.Storage.Registry.register(MyApp.S3Storage)

# Use it like any built-in backend
{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :s3,
  bucket: "my-zarr-data"
)
```

**Custom storage backend features:**

- Runtime registration and unregistration via Registry
- Behavior-based contract ensures all required operations are implemented
- Seamless integration with all ExZarr features (filters, compression, metadata)
- Can be configured via application config for automatic loading
- Thread-safe operations managed by OTP GenServer

**Required callbacks:**

- `backend_id/0` - Returns unique atom identifier
- `init/1` - Initialize storage with configuration
- `open/1` - Open existing storage location
- `read_chunk/2` - Read a chunk by index
- `write_chunk/3` - Write a chunk
- `read_metadata/1` - Read array metadata
- `write_metadata/3` - Write array metadata
- `list_chunks/1` - List all chunk indices
- `delete_chunk/2` - Delete a chunk
- `exists?/1` - Check if storage location exists

### Cloud and Database Storage Backends

ExZarr includes several pre-built storage backends for cloud services and databases:

#### AWS S3 Storage

```elixir
# Add dependencies
{:ex_aws, "~> 2.5"},
{:ex_aws_s3, "~> 2.5"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.S3)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :s3,
  bucket: "my-zarr-bucket",
  prefix: "experiments/array1",
  region: "us-west-2"
)
```

#### Azure Blob Storage

```elixir
# Add dependency
{:azure_sdk, "~> 0.4.1"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.AzureBlob)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :azure_blob,
  account_name: "mystorageaccount",
  account_key: System.get_env("AZURE_STORAGE_KEY"),
  container: "zarr-data",
  prefix: "experiments/array1"
)
```

#### Google Cloud Storage

```elixir
# Add dependencies
{:goth, "~> 1.4"},
{:req, "~> 0.6.1"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.GCS)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :gcs,
  bucket: "my-zarr-bucket",
  prefix: "experiments/array1",
  credentials: "/path/to/service-account.json"
)
```

#### Mnesia (Distributed Database)

```elixir
# No external dependencies - Mnesia is built into Erlang/OTP

# Initialize Mnesia
:mnesia.create_schema([node()])
:mnesia.start()

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mnesia)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :mnesia,
  array_id: "experiment_001",
  table_name: :zarr_storage
)
```

#### MongoDB GridFS

```elixir
# Add dependency
{:mongodb_driver, "~> 1.4"}

# Register and use
:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.MongoGridFS)

{:ok, array} = ExZarr.create(
  shape: {1000, 1000},
  chunks: {100, 100},
  storage: :mongo_gridfs,
  url: "mongodb://localhost:27017",
  database: "zarr_db",
  bucket: "arrays",
  array_id: "experiment_001"
)
```

#### Mock Storage (Testing)

```elixir
# No dependencies - built-in for testing

:ok = ExZarr.Storage.Registry.register(ExZarr.Storage.Backend.Mock)

# Test with error simulation
{:ok, array} = ExZarr.create(
  shape: {100},
  chunks: {10},
  storage: :mock,
  pid: self(),
  error_mode: :random,
  delay: 50  # Simulate 50ms latency
)

# Verify operations
assert_received {:mock_storage, :write_chunk, _}
```

**Cloud Storage Features:**

- S3, Azure Blob, and GCS backends provide scalable object storage
- Automatic credential management from environment/config
- Support for custom regions, buckets, and access patterns
- Thread-safe concurrent access

**Database Storage Features:**

- Mnesia provides distributed ACID transactions
- MongoDB GridFS handles large files (> 16MB chunks)
- Both support replication and high availability

**Mock Storage Features:**

- Error simulation (always fail, random, or specific operations)
- Latency simulation for performance testing
- Message tracking for verification
- State inspection for debugging

## Architecture

ExZarr uses:

- **Erlang :zlib** for zlib/gzip compression
- **[ExCodecs](https://hex.pm/packages/ex_codecs)** for zstd, lz4, snappy, blosc, bzip2 and
  crc32c (precompiled pure-Rust NIFs; ExZarr itself has no native code)
- **GenServer** for array state management
- **Lazy streams** (`Stream.resource/3`, `Task.async_stream/3`) for bounded-memory chunk I/O
- **Optional pipeline modules** (`ExZarr.Flow`, `ExZarr.GenStage`, `ExZarr.Broadway`) for backpressure and fault tolerance
- **`:telemetry`** for chunk read/write and stream lifecycle events
- **Pluggable storage backends** for memory, filesystem, zip, and cloud backends
- **Zarr v2 and v3 specifications** for interoperability with Python, Julia, and other Zarr implementations
- **Version-aware codec pipeline** that automatically routes between v2 and v3 implementations
- **Automatic format detection** when opening existing arrays

## Development

Requires **Elixir ~> 1.17** and **OTP 26+**. No native toolchain or system
libraries are needed; the codec NIFs come precompiled with ExCodecs.

```bash
# Install dependencies
mix deps.get

# Compile
mix compile

# Run tests
mix test

# Run tests with coverage
mix coveralls

# Run specific test suites
mix test test/ex_zarr_property_test.exs              # Property-based tests
mix test test/ex_zarr_python_integration_test.exs    # Python integration tests

# Run static analysis
mix credo

# Run type checking
mix dialyzer

# Generate documentation
mix docs
```

### Quality Checks

Before committing, ensure all quality checks pass:

```bash
# Run all tests
mix test

# Check code style
mix credo --strict

# Run type checker
mix dialyzer

# Verify test coverage
mix coveralls
```

### CI/CD

The project uses GitHub Actions for continuous integration. The CI pipeline:

- Tests on Elixir 1.17–1.19, 1.20-rc, and OTP 26–28 (Ubuntu)
- Runs all test suites (unit, integration, property-based)
- Performs code quality checks (Credo, Dialyzer, `mix format`)
- Generates test coverage reports and documentation (`mix docs --warnings-as-errors`)

## Testing

ExZarr includes comprehensive test coverage:

- **Unit tests** for individual modules and end-to-end workflows
- **Property-based tests** using StreamData (67 properties)
- **Doctests** across public modules (146 doctests)
- **Python integration tests** verifying interoperability with zarr-python
- **v3 integration tests** verifying Zarr v3 specification compliance
- **Streaming API tests** for `stream_chunks/2`, `stream_slices/3`, `write_stream/3`, and pipeline integrations
- **Custom codec tests** verifying the codec plugin system
- **Custom storage tests** verifying the storage backend plugin system
- **Total**: 1,526 tests + 67 properties + 146 doctests (229 cloud/integration tests excluded in default CI)

Key testing areas:

- Compression and decompression invariants
- Filter pipeline transformations (Delta, Quantize, Shuffle, etc.)
- Chunk index calculations for N-dimensional arrays
- Metadata round-trip serialization
- Storage backend operations (memory, filesystem, zip)
- Custom storage backend registration and usage
- Array creation and manipulation
- Edge cases and boundary conditions
- Zarr v2 specification compatibility with Python implementation
- Zarr v3 specification compliance (unified codec pipeline, new metadata format)
- v2/v3 interoperability and automatic version detection
- Custom codec registration and runtime behavior
- CRC32C checksum validation

### Python Integration Tests

ExZarr includes integration tests that verify compatibility with Python's zarr library.
Full local setup (v2 on Python 3.11, v3 on Python ≥ 3.12, fixtures, Mix tags) is in
**[Testing Python Interoperability](docs/INTEROPERABILITY.md#testing-python-interoperability)**.

```bash
# Zarr v3 example (Python ≥ 3.12)
python3.12 -m venv .venv-zarr3 && source .venv-zarr3/bin/activate
pip install 'zarr==3.4.0' numpy
OUT=/tmp/zarr_fixtures_v3
python test/support/python_fixtures/generate_fixtures.py --out "$OUT" --zarr-major 3
export EXZARR_PYTHON_FIXTURES="$OUT"
mix test --only python_fixtures
mix test --include python test/ex_zarr_v3_python_interop_test.exs
```

These tests verify that:

- ExZarr can read arrays created by zarr-python
- Python can read arrays created by ExZarr
- All 10 data types are compatible
- Metadata is correctly interpreted by both implementations
- Compression (zlib) works correctly across implementations

**Requirements**: Python 3.11+ (v2) or 3.12+ (v3), matching zarr-python, numpy

## Documentation

### Guides

Comprehensive guides for all skill levels:

- **[What is Zarr?](docs/guides/what_is_zarr.md)** — format overview
- **[Quick Start](#quick-start)** — create, write, read, save/open, and streaming
  - Installation and basic concepts
  - Creating and opening arrays
  - Reading and writing data
  - Streaming large arrays
  - Common patterns and best practices
- **[Advanced Usage](docs/guides/performance.md)** - Deep dive into advanced features
  - Zarr v3 features (sharding, dimension names, codec pipeline)
  - Custom chunk grids (regular and irregular)
  - Cloud storage optimization (S3, GCS, Azure)
  - Performance tuning and profiling
  - Custom storage backends and codecs
- **[Migration from Python](docs/guides/python_interop.md)** - For zarr-python users
  - API comparison and translation guide
  - Data structure differences (NumPy arrays vs nested tuples)
  - Converting between Python and Elixir
  - Interoperability examples
  - Common patterns and idioms

### Examples

Practical examples demonstrating real-world usage:

- **[Climate Data Processing](examples/climate_data.exs)** - Complete workflow for climate data
  - Multi-dimensional arrays with dimension names
  - Time-series data storage and analysis
  - Regional and temporal queries
  - Statistical computations
  - Compression and storage efficiency
- **[Sharded Cloud Storage](examples/sharded_cloud_storage.exs)** - Optimizing for S3/cloud storage
  - Comparing sharded vs non-sharded storage
  - Minimizing API calls and costs
  - Performance measurements
  - Configuration best practices
  - Cost analysis
- **[Dimension Names](examples/dimension_names.exs)** - Named dimension slicing
  - Creating arrays with semantic dimension labels
  - Intuitive slicing by name instead of index
  - Real-world examples (climate, medical imaging)
  - Validation and best practices
- **[Using Nx](docs/guides/getting_started.md#using-nx)**: what Nx is, when it fits, and how tensors and Zarr chunks exchange bytes
- **[Nx Integration](docs/guides/nx_integration.md)**: conversion API, chunk streams, and DataLoader
  - Converting between Nx tensors and Zarr arrays
  - Machine learning workflows
  - Streaming large arrays
  - Performance optimization
  - Batch processing
- **[Python Interoperability](examples/python_interop_demo.exs)** - Working with Python zarr
  - Reading Python-created arrays
  - Writing arrays for Python consumption
  - Data format compatibility
- **[S3 Storage](examples/s3_storage.exs)** - Using Amazon S3 as storage backend
  - S3 configuration and authentication
  - Creating and accessing S3-backed arrays
  - Performance optimization for cloud storage
- **[Custom Codec](examples/custom_codec_example.exs)** - Creating custom codecs
  - Implementing transformation and compression codecs
  - Registering codecs at runtime
  - Codec chaining and configuration

### API Documentation

Full API documentation is available at [hexdocs.pm/ex_zarr](https://hexdocs.pm/ex_zarr).

Key modules:

- **`ExZarr`** - Main API for creating and opening arrays
- **`ExZarr.Array`** - Array operations (reading, writing, slicing, streaming)
- **`ExZarr.Telemetry`** - Observability events for chunk I/O and streams
- **`ExZarr.Flow`**, **`ExZarr.GenStage`**, **`ExZarr.Broadway`** - Optional pipeline integrations
- **`ExZarr.Group`** - Hierarchical organization of arrays
- **`ExZarr.Metadata`** - Zarr v2 metadata handling
- **`ExZarr.MetadataV3`** - Zarr v3 metadata handling
- **`ExZarr.Storage.Backend`** - Storage backend behavior
- **`ExZarr.Codecs.Codec`** - Codec behavior for custom transformations
- **`ExZarr.ChunkGrid`** - Chunk grid configuration

## Roadmap

See [ROADMAP.md](docs/ROADMAP.md) for the full release plan.

**v1.3.1 (released 2026-10-09)** - Patch release: faster Nx chunk crops and
shuffled batches, livebooks checked in CI, measured performance figures. See
[release notes](docs/release_notes_v1_3_1.md).

**v1.3.0 (released 2026-10-08)** - Data science interop:
`ExZarr.Nx.stream_chunk_tensors/2`, DataLoader batch recipes, livebook MVP
(metadata, Nx conversion, minibatches, a small Axon train).

**v1.2.0 (released 2026-10-04)** - Zarr 3.1 interoperability & range-aware cloud I/O:
spec `sharding_indexed`, optional byte-range reads, version-aware cloud keys,
AzureSDK migration, codecs via ExCodecs (no native toolchain), `compressor_config`,
Python fixture/CI matrix.

**Upcoming** (high level):

- **v1.4.0** - **Performance & packaging**
  Async codec pipeline (overlap I/O + decode), vendored/static codecs, adaptive range coalescing,
  storage-transformer execution.
- **v2.0.0** - **Distributed processing**
  Horde/`:pg` multi-node chunk work, `PartitionSupervisor` pools, cross-node telemetry, distributed Broadway topologies.

## Contributing

Contributions are welcome. Please:

1. Fork the repository
2. Create a feature branch
3. Add tests for new functionality
4. Ensure all tests pass with `mix test`
5. Run code quality checks with `mix credo` and `mix dialyzer`
6. Submit a pull request

## License

MIT

## Credits

Inspired by [zarr-python](https://github.com/zarr-developers/zarr-python). Implements both Zarr v2 and v3 specifications for full compatibility with the broader Zarr ecosystem.