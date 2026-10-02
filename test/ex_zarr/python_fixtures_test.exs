defmodule ExZarr.PythonFixturesTest do
  @moduledoc """
  Reads stores written by zarr-python and compares every fixture against the
  SHA-256 recorded in the generator's manifest.

  Generate fixtures with `test/support/python_fixtures/generate_fixtures.py`,
  then run:

      EXZARR_PYTHON_FIXTURES=path/to/out mix test --only python_fixtures

  `EXZARR_PYTHON_FIXTURES` is a directory holding `manifest.json`, or a parent
  of several such directories.
  """

  use ExUnit.Case, async: true

  @moduletag :python_fixtures

  setup_all do
    root = System.get_env("EXZARR_PYTHON_FIXTURES")

    manifests =
      if root,
        do:
          Path.wildcard(Path.join(root, "manifest.json")) ++
            Path.wildcard(Path.join(root, "*/manifest.json")),
        else: []

    {:ok, root: root, manifests: manifests}
  end

  test "every zarr-python fixture reads back byte-identical", %{root: root, manifests: manifests} do
    assert root, "EXZARR_PYTHON_FIXTURES is not set"
    assert manifests != [], "no manifest.json under #{root}"

    for manifest_path <- manifests do
      manifest = manifest_path |> File.read!() |> Jason.decode!()
      dir = Path.dirname(manifest_path)
      assert manifest["fixtures"] != [], "#{manifest_path} lists no fixtures"

      for fixture <- manifest["fixtures"] do
        label = "#{fixture["name"]} (zarr-python #{manifest["zarr_python_version"]})"
        refute fixture["skipped"], "#{label} was skipped: #{fixture["reason"]}"

        {:ok, array} = ExZarr.open(path: Path.join(dir, fixture["path"]))
        shape = List.to_tuple(fixture["shape"])
        assert array.shape == shape, label

        {:ok, data} =
          ExZarr.Array.get_slice(array,
            start: Tuple.duplicate(0, tuple_size(shape)),
            stop: shape
          )

        digest = :crypto.hash(:sha256, data) |> Base.encode16(case: :lower)
        assert digest == fixture["sha256"], "#{label}: data mismatch"
      end
    end
  end
end
