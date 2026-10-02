#!/usr/bin/env python3
"""Generate compact ExZarr interoperability fixtures."""

from __future__ import annotations

import argparse
import hashlib
import json
import sys
from pathlib import Path

import numpy as np


def zarr_version() -> str:
    import zarr

    return zarr.__version__


def write_v2(out: Path) -> list[dict]:
    import zarr

    fixtures = []
    path = out / "v2_float64_2d"
    path.mkdir(parents=True, exist_ok=True)
    data = np.arange(20, dtype="float64").reshape(4, 5)
    arr = zarr.open(str(path), mode="w", shape=data.shape, chunks=(2, 5), dtype="float64")
    arr[:] = data
    fixtures.append(meta_entry("v2_float64_2d", path, data))
    return fixtures


def write_v3(out: Path) -> list[dict]:
    import zarr

    fixtures = []

    # scalar 0-D
    p = out / "v3_scalar"
    p.mkdir(parents=True, exist_ok=True)
    arr = zarr.open(str(p), mode="w", shape=(), chunks=(), dtype="float32", zarr_format=3)
    arr[()] = np.float32(3.5)
    fixtures.append(meta_entry("v3_scalar", p, np.array(3.5, dtype="float32")))

    # zero-length axis
    p = out / "v3_zero_len"
    p.mkdir(parents=True, exist_ok=True)
    data = np.zeros((0, 4), dtype="int32")
    arr = zarr.open(str(p), mode="w", shape=data.shape, chunks=(1, 4), dtype="int32", zarr_format=3)
    fixtures.append(meta_entry("v3_zero_len", p, data))

    # sharded if available
    try:
        from zarr.codecs import BytesCodec, sharding

        p = out / "v3_sharded"
        p.mkdir(parents=True, exist_ok=True)
        data = np.arange(16, dtype="int32").reshape(4, 4)
        # Prefer high-level API when present
        arr = zarr.create_array(
            str(p),
            shape=data.shape,
            chunks=(2, 2),
            dtype="int32",
            zarr_format=3,
            shards=(4, 4),
        )
        arr[:] = data
        fixtures.append(meta_entry("v3_sharded", p, data))
    except Exception as exc:  # noqa: BLE001
        fixtures.append(
            {
                "name": "v3_sharded",
                "skipped": True,
                "reason": str(exc),
            }
        )

    return fixtures


def meta_entry(name: str, path: Path, data: np.ndarray) -> dict:
    digest = hashlib.sha256(np.ascontiguousarray(data).tobytes()).hexdigest()
    return {
        "name": name,
        "path": str(path.name),
        "shape": list(data.shape),
        "dtype": str(data.dtype),
        "sha256": digest,
    }


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--out", type=Path, required=True)
    parser.add_argument("--zarr-major", type=int, choices=[2, 3], required=True)
    args = parser.parse_args()
    args.out.mkdir(parents=True, exist_ok=True)

    version = zarr_version()
    fixtures = write_v2(args.out) if args.zarr_major == 2 else write_v3(args.out)
    manifest = {
        "zarr_python_version": version,
        "zarr_major": args.zarr_major,
        "fixtures": fixtures,
    }
    (args.out / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps(manifest, indent=2))
    return 0


if __name__ == "__main__":
    sys.exit(main())
