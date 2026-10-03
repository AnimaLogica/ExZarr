# Release Checklist for ExZarr v1.2.0

Use this checklist when preparing and publishing the release.

## Pre-Release Preparation

### Code Quality
- [ ] All verification checks: `mix verify` (or individual: compile, format, credo, doctor, sobelow, dialyzer, test --cover, docs)
- [ ] No Credo warnings (`mix credo --strict`)
- [ ] Documentation builds clean (`mix docs --warnings-as-errors`)
- [ ] Dependencies reviewed (`mix deps.unlock --check-unused` optional)

### Documentation
- [x] `mix.exs` `@version` is `1.2.0`
- [x] README install uses `{:ex_zarr, "~> 1.2"}`
- [x] CHANGELOG.md has `[1.2.0]` entry
- [x] `docs/release_notes_v1_2_0.md` current
- [x] `docs/ROADMAP.md` marks v1.2.0 released; next is v1.3.0
- [x] `docs/INTEROPERABILITY.md` Python interop testing section current
- [x] GitHub org links use **AnimaLogica/ExZarr** (Hex `source_url`, badges, Zig NIF `base_url`)
- [ ] Examples / showcase reviewed (`examples/range_aware_sharded_nx.exs`)

### Version Numbers
- [x] `mix.exs` → `1.2.0`
- [x] Guides / livebooks / notebooks install snippets → `~> 1.2`
- [x] ZiglerPrecompiled `base_url` → `https://github.com/AnimaLogica/ExZarr/releases/download/v#{version}`
- [x] CHANGELOG comparison links include 1.2.0 / 1.1.0 / 1.0.0

### Testing
- [ ] `mix test`
- [ ] Python interop (see docs/INTEROPERABILITY.md): fixtures + `--include python` for v2 and v3
- [ ] Precompile dry-run locally if changing NIFs (`docs/PRECOMPILATION.md`)

## Git and GitHub

### Git Tags
- [ ] Commit all release-prep changes
- [ ] Tag: `git tag -a v1.2.0 -m "Release v1.2.0"`
- [ ] Push: `git push origin main && git push origin v1.2.0`
- [ ] Confirm tag on https://github.com/AnimaLogica/ExZarr

### Precompiled NIFs
- [ ] Wait for `.github/workflows/precompile.yml` to attach `.tar.gz` assets to the GitHub Release
- [ ] Generate checksums:
  ```bash
  EX_ZARR_BUILD=1 mix deps.get
  mix zigler_precompiled.download ExZarr.Codecs.ZigCodecs --all --print
  ```
- [ ] Commit `checksum-ExZarr.Codecs.ZigCodecs.exs`
- [ ] (Optional) mark `zigler` `optional: true` again once checksums ship — see `docs/PRECOMPILATION.md`

### GitHub Release
- [ ] Draft release for tag `v1.2.0`
- [ ] Title: `ExZarr v1.2.0 - Zarr 3.1 Interoperability & Range-Aware Cloud I/O`
- [ ] Body from `.github/RELEASE_ANNOUNCEMENT.md` / `docs/release_notes_v1_2_0.md`
- [ ] Ensure NIF assets from precompile workflow are attached
- [ ] Publish as latest release

## Hex.pm Publication

### Prepare
- [ ] Review `mix.exs` `package/0` (files include `checksum-*.exs`, CHANGELOG, LICENSE)
- [ ] `mix docs`
- [ ] `mix hex.build` and inspect `ex_zarr-1.2.0.tar`

### Publish
- [ ] `mix hex.publish --dry-run`
- [ ] `mix hex.publish`
- [ ] Verify https://hex.pm/packages/ex_zarr and https://hexdocs.pm/ex_zarr

## Announcements (optional)

- [ ] Elixir Forum / social posts using this announcement
- [ ] Elixir Weekly / Elixir Status if desired

## Post-Release

- [ ] Monitor issues on https://github.com/AnimaLogica/ExZarr/issues
- [ ] Confirm Coveralls / CI badges resolve under AnimaLogica
- [ ] Open v1.3.0 milestone items from `docs/ROADMAP.md`

## Rollback Plan (If Needed)

1. **Hex**: `mix hex.retire ex_zarr 1.2.0 --reason security` (or other reason), then publish a patch
2. **GitHub**: mark release as pre-release / yank NIF assets if corrupted; ship hotfix tag
3. **Comms**: update announcement channels and docs with workaround

## Release Date

- **Target**: 2026-10-03
- **Released**: _____________
- **Released by**: _____________
