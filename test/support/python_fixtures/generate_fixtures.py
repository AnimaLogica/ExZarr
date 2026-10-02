#!/usr/bin/env python3
"""Generate compact zarr-python fixtures for ExZarr interoperability tests.

Writes one store per fixture under --out plus a manifest.json recording the
zarr-python version and, per fixture, the expected shape, dtype and SHA-256
of the C-order little-endian array bytes. Any failure exits non-zero so CI
cannot silently lose coverage.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np
import zarr


def write_v2(out: Path) -> list[dict]:
    path = out / "v2_float64_2d"
    data = np.arange(20, dtype="float64").reshape(4, 5)
    arr = zarr.open(str(path), mode="w", shape=data.shape, chunks=(2, 5), dtype="float64")
    arr[:] = data
    return [entry("v2_float64_2d", path, data)]


def write_v3(out: Path) -> list[dict]:
    from zarr.codecs import BytesCodec, Crc32cCodec, ShardingCodec

    fixtures = []

    path = out / "v3_scalar"
    arr = zarr.create_array(str(path), shape=(), dtype="float32", zarr_format=3)
    arr[()] = np.float32(3.5)
    fixtures.append(entry("v3_scalar", path, np.array(3.5, dtype="float32")))

    path = out / "v3_zero_len"
    data = np.zeros((0, 4), dtype="int32")
    zarr.create_array(str(path), shape=data.shape, chunks=(1, 4), dtype="int32", zarr_format=3)
    fixtures.append(entry("v3_zero_len", path, data))

    # Default sharding: inner chunks 2x2 in one 4x4 shard, index at end with crc32c.
    path = out / "v3_sharded"
    data = np.arange(16, dtype="int32").reshape(4, 4)
    arr = zarr.create_array(
        str(path), shape=data.shape, chunks=(2, 2), shards=(4, 4), dtype="int32", zarr_format=3
    )
    arr[:] = data
    fixtures.append(entry("v3_sharded", path, data))

    # Index at start, uncompressed inner chunks, several shards and a partial
    # edge shard (shape not a multiple of the shard shape).
    path = out / "v3_sharded_index_start"
    data = np.arange(6 * 10, dtype="float64").reshape(6, 10)
    sharding = ShardingCodec(
        chunk_shape=(2, 2),
        codecs=[BytesCodec(endian="little")],
        index_codecs=[BytesCodec(endian="little"), Crc32cCodec()],
        index_location="start",
    )
    arr = zarr.create_array(
        str(path),
        shape=data.shape,
        chunks=(4, 4),
        dtype="float64",
        zarr_format=3,
        serializer=sharding,
        compressors=None,
    )
    arr[:] = data
    fixtures.append(entry("v3_sharded_index_start", path, data))

    # Big-endian inner chunks: the bytes codec must swap byte order.
    path = out / "v3_sharded_big_endian"
    data = (np.arange(12, dtype="int32").reshape(3, 4) * 1000) + 7
    sharding = ShardingCodec(chunk_shape=(2, 2), codecs=[BytesCodec(endian="big")])
    arr = zarr.create_array(
        str(path),
        shape=data.shape,
        chunks=(4, 4),
        dtype="int32",
        zarr_format=3,
        serializer=sharding,
        compressors=None,
    )
    arr[:] = data
    fixtures.append(entry("v3_sharded_big_endian", path, data))

    return fixtures


def entry(name: str, path: Path, data: np.ndarray) -> dict:
    little = np.ascontiguousarray(data).astype(data.dtype.newbyteorder("<"))
    return {
        "name": name,
        "path": path.name,
        "shape": list(data.shape),
        "dtype": str(data.dtype),
        "sha256": hashlib.sha256(little.tobytes()).hexdigest(),
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--zarr-major", type=int, choices=[2, 3], required=True)
    args = parser.parse_args()

    installed_major = int(zarr.__version__.split(".")[0])
    if installed_major != args.zarr_major:
        print(f"zarr {zarr.__version__} installed but --zarr-major {args.zarr_major}", file=sys.stderr)
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    fixtures = write_v2(args.out) if args.zarr_major == 2 else write_v3(args.out)
    manifest = {
        "zarr_python_version": zarr.__version__,
        "zarr_major": args.zarr_major,
        "fixtures": fixtures,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
