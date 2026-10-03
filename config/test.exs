import Config

# Test configuration — always build Zig NIFs from source in CI / local tests
config :zigler_precompiled, :force_build, ex_zarr: true
