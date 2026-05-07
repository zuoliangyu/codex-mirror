#!/usr/bin/env bash
#
# sync.sh — mirror OpenAI Codex release artifacts to local working dir,
# ready for `gh release create` upload by the workflow.
#
# Source:    https://github.com/openai/codex/releases (tag pattern: rust-v<VERSION>)
# Format:    .zst (smallest single-binary archive; app uses zstd crate to inflate)
# Hash:      SHA256 (we compute, mirror layout matches claude-code-mirror's manifest)
#
# Inputs (env):
#   WORK_DIR   stage dir (default: ./work)
#   CHANNEL    pin a specific tag like rust-v0.128.0 (default: latest)
#
# Output: $WORK_DIR/$VERSION/
#   manifest.json
#   {platform}-{asset}            (asset filename, flat, e.g. linux-x64-codex.zst)
#   SHA256SUMS

set -euo pipefail

WORK_DIR="${WORK_DIR:-./work}"
CHANNEL="${CHANNEL:-latest}"

# upstream platform name (codex naming) → our flat platform key
declare -A PLATFORM_MAP=(
  ["darwin-arm64"]="codex-aarch64-apple-darwin.zst"
  ["darwin-x64"]="codex-x86_64-apple-darwin.zst"
  ["linux-arm64"]="codex-aarch64-unknown-linux-musl.zst"
  ["linux-x64"]="codex-x86_64-unknown-linux-musl.zst"
  ["win32-arm64"]="codex-aarch64-pc-windows-msvc.exe.zst"
  ["win32-x64"]="codex-x86_64-pc-windows-msvc.exe.zst"
)

# inner binary name once decompressed (for manifest)
declare -A BINARY_NAME=(
  ["darwin-arm64"]="codex"
  ["darwin-x64"]="codex"
  ["linux-arm64"]="codex"
  ["linux-x64"]="codex"
  ["win32-arm64"]="codex.exe"
  ["win32-x64"]="codex.exe"
)

log() { echo "[sync] $*" >&2; }

# Resolve upstream tag → version string
if [[ "$CHANNEL" == "latest" ]]; then
  log "fetching latest release from openai/codex"
  TAG=$(curl -fsSL "https://api.github.com/repos/openai/codex/releases/latest" \
    | jq -r '.tag_name')
else
  TAG="$CHANNEL"
fi
if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  log "failed to resolve tag (got: '$TAG')"
  exit 1
fi

# tag is "rust-v0.128.0" → version "0.128.0"
VERSION="${TAG#rust-v}"
VERSION="${VERSION#v}"
log "tag=$TAG  version=$VERSION"

OUT="$WORK_DIR/$VERSION"
mkdir -p "$OUT"

UPSTREAM_BASE="https://github.com/openai/codex/releases/download/$TAG"

# Build manifest.platforms inline (jq composes at the end).
PLATFORMS_JSON="{}"

for plat in "${!PLATFORM_MAP[@]}"; do
  asset="${PLATFORM_MAP[$plat]}"
  binary="${BINARY_NAME[$plat]}"

  out_name="${plat}-${asset}"
  out_path="$OUT/$out_name"

  log "platform=$plat  asset=$asset"
  log "  downloading $UPSTREAM_BASE/$asset"
  curl -fsSL --retry 3 "$UPSTREAM_BASE/$asset" -o "$out_path"

  size=$(stat -c%s "$out_path" 2>/dev/null || stat -f%z "$out_path")
  checksum=$(sha256sum "$out_path" | cut -d' ' -f1)
  log "  size=$size  sha256=$checksum"

  PLATFORMS_JSON=$(jq --arg p "$plat" \
                     --arg asset "$out_name" \
                     --arg binary "$binary" \
                     --arg checksum "$checksum" \
                     --argjson size "$size" \
                     '. + {($p): {asset: $asset, binary: $binary, checksum: $checksum, size: $size}}' \
                     <<<"$PLATFORMS_JSON")
done

BUILD_DATE=$(date -u +%Y-%m-%dT%H:%M:%SZ)
jq -n \
  --arg version "$VERSION" \
  --arg upstream_tag "$TAG" \
  --arg build_date "$BUILD_DATE" \
  --argjson platforms "$PLATFORMS_JSON" \
  '{version: $version, upstream_tag: $upstream_tag, buildDate: $build_date, platforms: $platforms}' \
  > "$OUT/manifest.json"

# Plain SHA256SUMS for human verification
( cd "$OUT" && sha256sum *.zst > SHA256SUMS )

log "complete: $OUT"
echo "VERSION=$VERSION"
