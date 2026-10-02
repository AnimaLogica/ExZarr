defmodule ExZarr.Storage.CloudV3KeysTest do
  use ExUnit.Case, async: true

  alias ExZarr.Storage.ObjectKeys

  describe "ObjectKeys" do
    test "v2 metadata and chunk keys" do
      assert ObjectKeys.metadata_key("", 2) == ".zarray"
      assert ObjectKeys.metadata_key("data", 2) == "data/.zarray"
      assert ObjectKeys.chunk_key("", {0, 1}, 2) == "0.1"
      assert ObjectKeys.chunk_key("pref", {1, 2, 3}, 2) == "pref/1.2.3"
    end

    test "v3 metadata and chunk keys" do
      assert ObjectKeys.metadata_key("", 3) == "zarr.json"
      assert ObjectKeys.metadata_key("data", 3) == "data/zarr.json"
      assert ObjectKeys.chunk_key("", {0, 1}, 3) == "c/0/1"
      assert ObjectKeys.chunk_key("pref", {3, 4, 5}, 3) == "pref/c/3/4/5"
    end

    test "parse round-trip" do
      key = ObjectKeys.chunk_key("arrays/exp", {2, 3}, 3)
      assert ObjectKeys.parse_chunk_key(key, "arrays/exp", 3) == {2, 3}
    end
  end
end
