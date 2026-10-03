# Precompiled Zig NIFs

ExZarr ships precompiled `ZigCodecs` NIFs via
[ZiglerPrecompiled](https://hex.pm/packages/zigler_precompiled) so Hex and
Livebook users do not need a Zig toolchain.

## Supported targets

- `x86_64-linux-gnu`
- `aarch64-linux-gnu`
- `aarch64-macos-none`
- `x86_64-windows-gnu`

Artifacts are built **natively** on each OS (no cross-link against system
compression libs). They still **dynamically link** `zstd`, `lz4`, `snappy`,
`blosc`, and `bz2` at runtime — install those packages on the host.
Windows CI uses MSYS2 UCRT64 packages for the link step.

## Force a source build

```bash
EX_ZARR_BUILD=1 mix compile
```

Or in config:

```elixir
config :zigler_precompiled, :force_build, ex_zarr: true
```

Dev/test configs already force a source build. If
`checksum-ExZarr.Codecs.ZigCodecs.exs` is missing, source build is also forced.

Until checksums are published, `zigler` is a **required** dependency so
`Mix.install` / path Livebooks pull it (optional deps are not fetched for
dependencies). After Hex ships with checksums, `zigler` can be marked
`optional: true` again.

## Release flow

1. Tag: `git tag v1.2.0 && git push origin v1.2.0`
2. Wait for `.github/workflows/precompile.yml` to upload `.tar.gz` assets to the
   GitHub Release
3. Generate checksums (from a machine that can download the assets):

   ```bash
   EX_ZARR_BUILD=1 mix deps.get
   mix zigler_precompiled.download ExZarr.Codecs.ZigCodecs --all --print
   ```

4. Commit `checksum-ExZarr.Codecs.ZigCodecs.exs`
5. Publish to Hex (`mix hex.publish`) — the checksum file is included in
   `package.files`

## Local artifact (smoke)

```bash
EX_ZARR_BUILD=1 mix zigler_precompiled.build \
  lib/ex_zarr/codecs/zig_codecs.ex \
  --target aarch64-macos-none \
  --out artifacts
```

Replace the target with your host triple from
`ZiglerPrecompiled.current_target_triple()`.
