#!/usr/bin/env bash
#
# sync-npm.sh — mirror @openai/codex npm tarballs.
#
# Codex uses a single-package + version-alias trick: all platform binaries are
# stored as alternate version tags of `@openai/codex` itself, e.g.
# `0.128.0-linux-x64` instead of as separate `@openai/codex-linux-x64` packages.
# (Claude Code uses the per-platform-package convention; we have to handle both.)
#
# Inputs (env):
#   VERSION    Required. Base version, e.g. "0.128.0".
#   WORK_DIR   stage dir (default: ./work)
#
# Output: $WORK_DIR/$VERSION/npm/
#   *.tgz                   one tarball per (base + 6 platform variants)
#   npm-manifest.json       version + sha256 of each tarball

set -euo pipefail

VERSION="${VERSION:?VERSION required}"
WORK_DIR="${WORK_DIR:-./work}"

REGISTRY="https://registry.npmjs.org"
SCOPE="@openai/codex"
UNSCOPED="codex"

# Each entry is "<version-suffix> <platform-label>" — empty suffix = main package.
TARGETS=(
  ""             # base package
  "linux-x64"
  "linux-arm64"
  "darwin-x64"
  "darwin-arm64"
  "win32-x64"
  "win32-arm64"
)

OUT="$WORK_DIR/$VERSION/npm"
mkdir -p "$OUT"

log() { echo "[sync-npm] $*" >&2; }

PACKAGES_JSON="[]"

for suffix in "${TARGETS[@]}"; do
  if [[ -z "$suffix" ]]; then
    pkg_version="$VERSION"
    label="main"
  else
    pkg_version="${VERSION}-${suffix}"
    label="$suffix"
  fi

  url="$REGISTRY/$SCOPE/-/$UNSCOPED-$pkg_version.tgz"
  out_name="${UNSCOPED}-${pkg_version}.tgz"
  out_path="$OUT/$out_name"

  log "$SCOPE @ $pkg_version  ($label)"
  log "  GET $url"
  if ! curl -fsSL --retry 3 -o "$out_path" "$url"; then
    log "  ✗ failed"
    continue
  fi

  size=$(stat -c%s "$out_path" 2>/dev/null || stat -f%z "$out_path")
  checksum=$(sha256sum "$out_path" | cut -d' ' -f1)
  log "  ✓ $size bytes, sha256=$checksum"

  PACKAGES_JSON=$(jq \
    --arg name "$SCOPE" \
    --arg version "$pkg_version" \
    --arg label "$label" \
    --arg tgz "$out_name" \
    --arg checksum "$checksum" \
    --argjson size "$size" \
    '. + [{name: $name, version: $version, label: $label, tgz: $tgz, checksum: $checksum, size: $size}]' \
    <<<"$PACKAGES_JSON")
done

BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg version "$VERSION" \
  --arg synced_at "$BUILD_DATE" \
  --arg registry "$REGISTRY" \
  --argjson packages "$PACKAGES_JSON" \
  '{version: $version, synced_at: $synced_at, registry: $registry, packages: $packages}' \
  > "$OUT/npm-manifest.json"

log "complete: $OUT"
ls -la "$OUT"
