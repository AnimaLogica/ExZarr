defmodule ExZarr.Storage.CloudV3KeysTest do
  use ExUnit.Case, async: true
  use ExUnitProperties

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

    test "v3 chunk_key_encoding is honoured" do
      dot = %{"name" => "default", "configuration" => %{"separator" => "."}}
      v2 = %{name: "v2"}

      assert ObjectKeys.chunk_key("p", {1, 2}, 3, dot) == "p/c.1.2"
      assert ObjectKeys.chunk_key("p", {1, 2}, 3, v2) == "p/1.2"
      assert ObjectKeys.chunk_key("", {}, 3) == "c"
      assert ObjectKeys.parse_chunk_key("p/c.1.2", "p", 3, dot) == {1, 2}
      assert ObjectKeys.parse_chunk_key("p/1.2", "p", 3, v2) == {1, 2}
      assert ObjectKeys.parse_chunk_key("c", "", 3) == {}
    end

    test "prefix is stripped exactly once" do
      assert ObjectKeys.parse_chunk_key("c/c/0/1", "c", 3) == {0, 1}
      assert ObjectKeys.parse_chunk_key("0/0.1", "0", 2) == {0, 1}
    end

    test "objects outside the prefix or in nested nodes are not chunks" do
      # sibling prefix
      assert ObjectKeys.parse_chunk_key("data2/c/0", "data", 3) == nil
      # nested array under the prefix
      assert ObjectKeys.parse_chunk_key("a/a/1", "a", 2) == nil
      assert ObjectKeys.parse_chunk_key("grp/arr/c/0", "grp", 3) == nil
      # metadata
      assert ObjectKeys.parse_chunk_key("p/zarr.json", "p", 3) == nil
      assert ObjectKeys.parse_chunk_key("p/.zarray", "p", 2) == nil
    end

    test "metadata_version reads zarr_format" do
      assert ObjectKeys.metadata_version(~s({"zarr_format": 3}), 2) == 3
      assert ObjectKeys.metadata_version(~s({"zarr_format": 2}), 3) == 2
      assert ObjectKeys.metadata_version("not json", 2) == 2
    end

    test "config_layout accepts zarr_format or zarr_version" do
      assert {:ok, %{zarr_format: 3}} = ObjectKeys.config_layout(zarr_version: 3)
      assert {:ok, %{zarr_format: 3}} = ObjectKeys.config_layout(zarr_format: 3)
      assert {:ok, %{zarr_format: 2}} = ObjectKeys.config_layout([])
      assert {:error, {:invalid_zarr_format, 4}} = ObjectKeys.config_layout(zarr_format: 4)
    end
  end

  property "chunk keys round-trip for any prefix, version and encoding" do
    segment = StreamData.member_of(["c", "0", "a", "data", "x1", "arr"])

    check all(
            prefix_parts <- StreamData.list_of(segment, max_length: 3),
            index <- StreamData.list_of(StreamData.integer(0..500), min_length: 1, max_length: 4),
            {version, encoding} <-
              StreamData.member_of([
                {2, nil},
                {3, nil},
                {3, %{name: "default", configuration: %{separator: "."}}},
                {3, %{name: "v2"}},
                {3, %{name: "v2", configuration: %{separator: "/"}}}
              ])
          ) do
      prefix = Enum.join(prefix_parts, "/")
      index = List.to_tuple(index)
      key = ObjectKeys.chunk_key(prefix, index, version, encoding)
      assert ObjectKeys.parse_chunk_key(key, prefix, version, encoding) == index
    end
  end
end
