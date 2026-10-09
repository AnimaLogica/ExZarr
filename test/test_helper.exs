# Exclude tests that require external services by default
# These backends require external services, credentials, or special setup:
# - :s3     - AWS S3 (requires credentials)
# - :gcs    - Google Cloud Storage (requires credentials)
# - :azure  - Azure Blob Storage (requires credentials)
# - :mongo  - MongoDB GridFS (requires MongoDB running)
# - :mnesia - Mnesia distributed database (requires Mnesia setup)
# - :python - Python zarr-python integration tests (requires Python + zarr + numpy)
# - :python_fixtures - zarr-python fixture manifest check (needs EXZARR_PYTHON_FIXTURES)
#
# CI runs only self-contained backends: Memory, ETS, Mock, Filesystem, Zip
# Nx unit tests run by default (Nx is a project dependency).
#
# To run live cloud/Python tests locally:
#   mix test --include s3 --include gcs --include azure --include mongo --include mnesia --include python
#
# Wall-clock and memory benchmarks are also excluded by default:
# - :performance - asserts elapsed time (e.g. an 8 MB conversion under 5 s)
# - :memory      - asserts memory growth while streaming
# Their results depend on how loaded the machine is, so on shared CI runners
# they fail without any code change. CI runs them in the non-blocking
# "Benchmarks" job. Run them locally with:
#   mix test --only performance --only memory
ExUnit.configure(
  exclude: [:s3, :gcs, :azure, :mongo, :mnesia, :python, :python_fixtures, :performance, :memory]
)

ExUnit.start()
