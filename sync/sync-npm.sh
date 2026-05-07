#!/usr/bin/env bash
#
# sync-npm.sh — mirror @openai/codex + platform subpackages as .tgz.
#
# Inputs (env):
#   VERSION    Required. The npm package version (e.g. "0.128.0").
#   WORK_DIR   stage dir (default: ./work)
#
# Output: $WORK_DIR/$VERSION/npm/
#   *.tgz                   one tarball per package
#   npm-manifest.json       version + sha256 of each tarball

set -euo pipefail

VERSION="${VERSION:?VERSION required}"
WORK_DIR="${WORK_DIR:-./work}"

PACKAGES=(
  "@openai/codex"
  "@openai/codex-darwin-arm64"
  "@openai/codex-darwin-x64"
  "@openai/codex-linux-arm64"
  "@openai/codex-linux-x64"
  "@openai/codex-win32-arm64"
  "@openai/codex-win32-x64"
)

REGISTRY="https://registry.npmjs.org"

OUT="$WORK_DIR/$VERSION/npm"
mkdir -p "$OUT"

log() { echo "[sync-npm] $*" >&2; }

tarball_url() {
  local pkg="$1" version="$2"
  local unscoped="${pkg##*/}"
  echo "$REGISTRY/$pkg/-/$unscoped-$version.tgz"
}

PACKAGES_JSON="[]"

for pkg in "${PACKAGES[@]}"; do
  url=$(tarball_url "$pkg" "$VERSION")
  unscoped="${pkg##*/}"
  out_name="${unscoped}-${VERSION}.tgz"
  out_path="$OUT/$out_name"

  log "$pkg @ $VERSION"
  log "  GET $url"
  if ! curl -fsSL --retry 3 -o "$out_path" "$url"; then
    log "  ✗ failed (package may not exist on npm at this version)"
    continue
  fi

  size=$(stat -c%s "$out_path" 2>/dev/null || stat -f%z "$out_path")
  checksum=$(sha256sum "$out_path" | cut -d' ' -f1)
  log "  ✓ $size bytes, sha256=$checksum"

  PACKAGES_JSON=$(jq \
    --arg name "$pkg" \
    --arg version "$VERSION" \
    --arg tgz "$out_name" \
    --arg checksum "$checksum" \
    --argjson size "$size" \
    '. + [{name: $name, version: $version, tgz: $tgz, checksum: $checksum, size: $size}]' \
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
