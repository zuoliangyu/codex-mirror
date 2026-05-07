#!/usr/bin/env bash
#
# sync.sh — mirror OpenAI Codex release artifacts to local working dir.
#
# Source: https://github.com/openai/codex/releases (tag: rust-v<VERSION>)
# Format: .zst (smallest single-binary archive)
# Hash:   SHA256 (computed locally)
#
# Asset naming uses the same flat `{platform}-{binary}` convention as
# claude-code-mirror, so the ai-cli-installer app can reuse its existing
# Mirror::GhRelease URL builder. The `binary` field in manifest is the
# downloaded filename (includes .zst); `runtime_binary` is the file you
# get after zstd decompression — the actual executable.
#
# Inputs (env):
#   WORK_DIR  stage dir   (default: ./work)
#   CHANNEL   pin tag     (default: latest, e.g. rust-v0.128.0)
#
# Output: $WORK_DIR/$VERSION/
#   manifest.json
#   {platform}-{binary}      (e.g. linux-x64-codex.zst, win32-x64-codex.exe.zst)
#   SHA256SUMS

set -euo pipefail

WORK_DIR="${WORK_DIR:-./work}"
CHANNEL="${CHANNEL:-latest}"

# upstream platform name → upstream asset name + our flat binary name + final runtime name
declare -A UPSTREAM_ASSET=(
  ["darwin-arm64"]="codex-aarch64-apple-darwin.zst"
  ["darwin-x64"]="codex-x86_64-apple-darwin.zst"
  ["linux-arm64"]="codex-aarch64-unknown-linux-musl.zst"
  ["linux-x64"]="codex-x86_64-unknown-linux-musl.zst"
  ["win32-arm64"]="codex-aarch64-pc-windows-msvc.exe.zst"
  ["win32-x64"]="codex-x86_64-pc-windows-msvc.exe.zst"
)

# Our flat name (the {binary} part of {platform}-{binary} on our release).
# Includes .zst because the file user downloads IS a zst archive.
declare -A FLAT_BINARY=(
  ["darwin-arm64"]="codex.zst"
  ["darwin-x64"]="codex.zst"
  ["linux-arm64"]="codex.zst"
  ["linux-x64"]="codex.zst"
  ["win32-arm64"]="codex.exe.zst"
  ["win32-x64"]="codex.exe.zst"
)

# Final runtime binary name (after zstd decompression).
declare -A RUNTIME_BIN=(
  ["darwin-arm64"]="codex"
  ["darwin-x64"]="codex"
  ["linux-arm64"]="codex"
  ["linux-x64"]="codex"
  ["win32-arm64"]="codex.exe"
  ["win32-x64"]="codex.exe"
)

log() { echo "[sync] $*" >&2; }

# Resolve upstream tag → version
if [[ "$CHANNEL" == "latest" ]]; then
  log "fetching latest release from openai/codex"
  TAG=$(curl -fsSL "https://api.github.com/repos/openai/codex/releases/latest" \
    | jq -r '.tag_name')
else
  TAG="$CHANNEL"
fi
if [[ -z "$TAG" || "$TAG" == "null" ]]; then
  log "failed to resolve tag"
  exit 1
fi

VERSION="${TAG#rust-v}"
VERSION="${VERSION#v}"
log "tag=$TAG version=$VERSION"

OUT="$WORK_DIR/$VERSION"
mkdir -p "$OUT"

UPSTREAM_BASE="https://github.com/openai/codex/releases/download/$TAG"

PLATFORMS_JSON="{}"

for plat in "${!UPSTREAM_ASSET[@]}"; do
  upstream_name="${UPSTREAM_ASSET[$plat]}"
  flat="${FLAT_BINARY[$plat]}"
  runtime="${RUNTIME_BIN[$plat]}"

  out_name="${plat}-${flat}"
  out_path="$OUT/$out_name"

  log "platform=$plat upstream=$upstream_name → out=$out_name"
  log "  GET $UPSTREAM_BASE/$upstream_name"
  curl -fsSL --retry 3 "$UPSTREAM_BASE/$upstream_name" -o "$out_path"

  size=$(stat -c%s "$out_path" 2>/dev/null || stat -f%z "$out_path")
  checksum=$(sha256sum "$out_path" | cut -d' ' -f1)
  log "  size=$size sha256=$checksum"

  PLATFORMS_JSON=$(jq --arg p "$plat" \
                     --arg binary "$flat" \
                     --arg runtime_binary "$runtime" \
                     --arg checksum "$checksum" \
                     --argjson size "$size" \
                     '. + {($p): {binary: $binary, runtime_binary: $runtime_binary, checksum: $checksum, size: $size}}' \
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

( cd "$OUT" && sha256sum *.zst > SHA256SUMS )

log "complete: $OUT"
echo "VERSION=$VERSION"
