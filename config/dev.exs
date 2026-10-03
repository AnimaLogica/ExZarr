import Config

# Development configuration — always build Zig NIFs from source locally
config :zigler_precompiled, :force_build, ex_zarr: true
