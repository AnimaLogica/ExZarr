# Installation and Build Toolchain

This guide covers installing ExZarr, checking that its compression codecs are available, and troubleshooting common build issues. Follow these steps to get ExZarr running reliably on macOS, Linux, or in CI environments.

## Prerequisites

### Required Software

**Elixir and Erlang/OTP:**
- Elixir 1.17 or later
- Erlang/OTP 26 or later

Check your versions:
```bash
elixir --version
# Erlang/OTP 26 [erts-14.0] [source] [64-bit] [smp:8:8] [ds:8:8:10]
# Elixir 1.17.0 (compiled with Erlang/OTP 26)
```

These versions are required because ExZarr uses modern Elixir features, and the precompiled codec NIFs (from ExCodecs) target NIF version 2.17, which needs OTP 26 or later.

**Operating System Support:**
- macOS (Intel and Apple Silicon)
- Linux (Ubuntu/Debian, Fedora/RHEL, Arch)
- Windows (x86_64)

### Native Dependencies

No native toolchain or system libraries are needed. All codecs other than
`:zlib` and `:gzip` come from [ExCodecs](https://hex.pm/packages/ex_codecs),
whose pure-Rust NIFs are downloaded precompiled for your platform (macOS,
Linux glibc and musl, Windows x86_64) when you run `mix deps.get`.

## Mix Dependency Installation

### Basic Installation

Add ExZarr to your `mix.exs` dependencies:

```elixir
def deps do
  [
    {:ex_zarr, "~> 1.3"}
  ]
end
```

Then fetch dependencies:
```bash
mix deps.get
```

This installs ExZarr with its required dependencies: Jason (JSON), Telemetry, and ExCodecs (compression codecs, precompiled NIFs).

### Optional Dependencies

For cloud storage backends, add the appropriate libraries:

**AWS S3:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.3"},
    {:ex_aws, "~> 2.5"},
    {:ex_aws_s3, "~> 2.5"},
    {:sweet_xml, "~> 0.7"}  # For XML response parsing
  ]
end
```

**Google Cloud Storage:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.3"},
    {:goth, "~> 1.4"},      # Authentication
    {:req, "~> 0.6.1"}      # HTTP client
  ]
end
```

**Azure Blob Storage:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.3"},
    {:azure_sdk, "~> 0.4.1"}
  ]
end
```

**MongoDB GridFS:**
```elixir
def deps do
  [
    {:ex_zarr, "~> 1.3"},
    {:mongodb_driver, "~> 1.4"}
  ]
end
```

These dependencies are marked as `optional: true` in ExZarr's `mix.exs`, so they're only included when you explicitly add them.

### Compilation

Compile the project:
```bash
mix compile
```

No native code is compiled: ExCodecs downloads its precompiled NIF during
`mix deps.compile` and verifies it against the checksums shipped in the
package. The first build takes well under a minute.

## Verifying Codec Availability

After compilation, check which codecs are available:

```elixir
iex -S mix

iex> ExZarr.Codecs.available_codecs()
[:none, :zlib, :crc32c, :zstd, :lz4, :snappy, :blosc, :bzip2]
```

If only `:none` and `:zlib` are listed, the ExCodecs NIF failed to load; see
[Codec Not Available](#issue-codec-not-available).

## Verifying Installation

### Quick Verification Test

Run this in IEx to verify ExZarr is working:

```elixir
# Start IEx
iex -S mix

# Create a small in-memory array
iex> {:ok, array} = ExZarr.create(
  shape: {10, 10},
  chunks: {5, 5},
  dtype: :float64,
  storage: :memory
)
{:ok, %ExZarr.Array{...}}

# Write some data
iex> data = Tuple.duplicate(Tuple.duplicate(1.0, 10), 10)
iex> :ok = ExZarr.Array.set_slice(array, data, start: {0, 0}, stop: {10, 10})
:ok

# Read it back
iex> {:ok, retrieved} = ExZarr.Array.get_slice(array, start: {0, 0}, stop: {10, 10})
{:ok, {{1.0, 1.0, ...}, ...}}

# Verify data matches
iex> data == retrieved
true
```

If this works, ExZarr is installed correctly.

### Comprehensive Verification

Run the test suite:

```bash
# Run all tests
mix test

# Should see output like:
# ..................................................
# Finished in 2.3 seconds (0.1s async, 2.2s sync)
# 466 tests, 0 failures
```

If tests pass, your installation is complete and working correctly.

### Check Installed Version

```elixir
iex> Application.spec(:ex_zarr, :vsn) |> to_string()
"1.3.1"
```

## Build Troubleshooting

### Issue: Codec Not Available

**Symptom:** `ExZarr.Codecs.available_codecs()` lists only `:none` and `:zlib`.

**Cause:** the ExCodecs NIF did not load. Usually the precompiled download
failed (offline build, proxy) or the platform has no precompiled binary.

**Solutions:**

1. Re-fetch and rebuild the dependency with network access:
   ```bash
   mix deps.clean ex_codecs --build
   mix deps.get && mix deps.compile ex_codecs
   ```
2. On a platform without a precompiled binary, build ExCodecs from source
   (needs a Rust toolchain):
   ```elixir
   # mix.exs
   {:rustler, ">= 0.0.0", optional: true}

   # config/config.exs
   config :rustler_precompiled, :force_build, ex_codecs: true
   ```
3. Meanwhile `:zlib` (and `:gzip` on Zarr v3 arrays) keep working; they use
   Erlang's built-in `:zlib`.

### Issue: Permission Denied Errors

**Symptom:**
```
** (File.Error) could not write to file "_build/dev/lib/ex_zarr/ebin/Elixir.ExZarr.beam": permission denied
```

**Cause:**
Build directory has incorrect permissions, often from running `sudo mix` previously.

**Fix:**
```bash
# Fix ownership
sudo chown -R $USER _build deps

# Clean and rebuild
mix deps.clean --all
mix deps.get
mix compile
```

**Prevention:**
Never run `mix` commands with `sudo`. If you need system-wide installation, use proper Elixir version management (asdf, mise).

## CI/CD Configuration

### GitHub Actions Example

Complete workflow for testing ExZarr in CI. No system packages or native
toolchains are needed.

```yaml
name: CI

on:
  push:
    branches: [ main ]
  pull_request:
    branches: [ main ]

jobs:
  test:
    runs-on: ubuntu-latest
    strategy:
      matrix:
        elixir: ['1.17', '1.18', '1.19']
        otp: ['26', '27', '28']

    steps:
    - uses: actions/checkout@v4

    - name: Set up Elixir
      uses: erlef/setup-beam@v1
      with:
        elixir-version: ${{ matrix.elixir }}
        otp-version: ${{ matrix.otp }}

    - name: Cache deps and build
      uses: actions/cache@v4
      with:
        path: |
          deps
          _build
        key: ${{ runner.os }}-mix-${{ matrix.otp }}-${{ matrix.elixir }}-${{ hashFiles('**/mix.lock') }}

    - name: Install dependencies
      run: mix deps.get

    - name: Compile
      run: mix compile --warnings-as-errors

    - name: Run tests
      run: mix test

    - name: Check formatting
      run: mix format --check-formatted

    - name: Run Credo
      run: mix credo --strict
```

### Docker Example

Dockerfile for an ExZarr application. The ExCodecs NIF is precompiled for
both glibc and musl (Alpine), so no compression packages are needed:

```dockerfile
FROM elixir:1.18-alpine AS builder

RUN apk add --no-cache build-base git

WORKDIR /app

RUN mix local.hex --force && \
    mix local.rebar --force

COPY mix.exs mix.lock ./
RUN mix deps.get --only prod

COPY . .

RUN MIX_ENV=prod mix compile

FROM elixir:1.18-alpine

WORKDIR /app

COPY --from=builder /app/_build/prod /app/_build/prod
COPY --from=builder /app/deps /app/deps

CMD ["iex", "-S", "mix"]
```

### GitLab CI Example

```yaml
image: elixir:1.18

cache:
  paths:
    - deps/
    - _build/

before_script:
  - mix local.hex --force
  - mix local.rebar --force
  - mix deps.get

test:
  script:
    - mix compile --warnings-as-errors
    - mix test
    - mix credo --strict
```

### Caching Best Practices

**Always cache:**
- `deps/` - Mix dependencies (including the downloaded ExCodecs NIF)
- `_build/` - Compiled artifacts

**Cache keys should include:**
- OS/platform
- Elixir/OTP versions
- `mix.lock` hash (invalidate on dependency changes)

## Next Steps

Now that ExZarr is installed:

1. **Try the Quick Start**: See [README — Quick Start](../../README.md#quick-start) for a working example
2. **Learn Core Concepts**: Understand chunking and codecs in [Core Concepts Guide](core_concepts.md)
3. **Configure Storage**: Set up S3 or other backends in [Storage Providers Guide](storage_providers.md)
4. **Optimize Performance**: Tune chunk sizes and compression in [Performance Guide](performance.md)

## Getting Help

If you encounter issues not covered here:

1. Check [Troubleshooting Guide](troubleshooting.md) for more solutions
2. Verify your environment matches [Prerequisites](#prerequisites)
3. Search [GitHub Issues](https://github.com/AnimaLogica/ExZarr/issues)
4. Open a new issue with your environment details and error messages

Include in bug reports:
```bash
# Gather environment info
elixir --version
mix --version
uname -a
ls -la _build/dev/lib/ex_zarr/priv/  # Check for .so files
```
