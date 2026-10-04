#!/usr/bin/env python3
"""Regenerate numcodecs (zarr-python) codec fixtures for ExZarr.

    pip install numcodecs
    python test/fixtures/numcodecs/generate.py

Payload: 40_000 bytes, byte i = (i * 7 + i // 3) % 251 (same as the tests).
"""
from pathlib import Path

import numcodecs
from numcodecs import BZ2, LZ4, Blosc, Zstd

HERE = Path(__file__).parent
payload = bytes((i * 7 + i // 3) % 251 for i in range(40_000))

codecs = {
    "zstd": Zstd(level=3),
    "lz4": LZ4(),
    "bz2": BZ2(level=9),
    "blosc_blosclz_shuffle": Blosc(cname="blosclz", clevel=5, shuffle=Blosc.SHUFFLE),
    "blosc_lz4_bitshuffle": Blosc(cname="lz4", clevel=5, shuffle=Blosc.BITSHUFFLE),
    "blosc_zstd_noshuffle": Blosc(cname="zstd", clevel=5, shuffle=Blosc.NOSHUFFLE),
}

for name, codec in codecs.items():
    (HERE / f"{name}.bin").write_bytes(bytes(codec.encode(payload)))

print("numcodecs", numcodecs.__version__, "->", sorted(codecs))
