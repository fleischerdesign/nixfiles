#!/usr/bin/env bash
# lib/updaters/update-custom-packages.sh
# Universal auto-update engine for custom packages defined in packages/custom/*/manifest.json

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
CUSTOM_PKGS_DIR="$REPO_ROOT/packages/custom"
TARGET_PKG="${1:-all}"

if [ ! -d "$CUSTOM_PKGS_DIR" ]; then
  echo "No packages/custom directory found at $CUSTOM_PKGS_DIR"
  exit 0
fi

echo "🔍 Checking custom packages for upstream updates..."

for manifest_path in "$CUSTOM_PKGS_DIR"/*/manifest.json; do
  [ -f "$manifest_path" ] || continue

  pkg_dir="$(dirname "$manifest_path")"
  pkg_name="$(basename "$pkg_dir")"

  if [ "$TARGET_PKG" != "all" ] && [ "$TARGET_PKG" != "$pkg_name" ]; then
    continue
  fi

  echo "--------------------------------------------------"
  echo "📦 Processing $pkg_name..."

  upstream_type="$(jq -r '.upstream.type // "none"' "$manifest_path")"
  current_version="$(jq -r '.version' "$manifest_path")"

  if [ "$upstream_type" = "github-release" ]; then
    owner="$(jq -r '.upstream.owner' "$manifest_path")"
    repo="$(jq -r '.upstream.repo' "$manifest_path")"

    echo "  Current version: $current_version"
    echo "  Checking GitHub upstream: $owner/$repo..."

    API_URL="https://api.github.com/repos/$owner/$repo/releases/latest"
    if [ -n "${GITHUB_TOKEN:-}" ]; then
      RELEASE_JSON="$(curl -s -H "Authorization: token $GITHUB_TOKEN" "$API_URL")"
    else
      RELEASE_JSON="$(curl -s "$API_URL")"
    fi

    latest_tag="$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty' | sed 's/^v//')"

    if [ -z "$latest_tag" ]; then
      echo "  ⚠️ Could not fetch latest release tag for $owner/$repo"
      continue
    fi

    if [ "$latest_tag" = "$current_version" ]; then
      echo "  ✅ $pkg_name is already up to date (v$current_version)."
      continue
    fi

    echo "  🎉 New version available: v$latest_tag (current: v$current_version)"

    asset_name="$(echo "$RELEASE_JSON" | jq -r --arg ver "$latest_tag" '.assets[].name | select(test($ver) and endswith(".AppImage"))' | head -n 1)"
    if [ -z "$asset_name" ]; then
      asset_name="$(echo "$RELEASE_JSON" | jq -r '.assets[].name | select(endswith(".AppImage"))' | head -n 1)"
    fi

    if [ -z "$asset_name" ]; then
      echo "  ⚠️ Could not find matching AppImage asset in release v$latest_tag"
      continue
    fi

    download_url="https://github.com/$owner/$repo/releases/download/v$latest_tag/$asset_name"
    echo "  Downloading and hashing $download_url..."

    new_hash="$(nix store prefetch-file "$download_url" --json | jq -r '.hash')"

    if [ -z "$new_hash" ] || [ "$new_hash" = "null" ]; then
      echo "  ❌ Failed to calculate SRI hash for $download_url"
      continue
    fi

    tmp_manifest="$(mktemp)"
    jq --arg ver "$latest_tag" \
       --arg hash "$new_hash" \
       --arg asset "$asset_name" \
       '.version = $ver | .hash = $hash | .upstream.assetName = $asset' \
       "$manifest_path" > "$tmp_manifest"

    mv "$tmp_manifest" "$manifest_path"
    echo "  ✨ Updated $pkg_name to v$latest_tag with hash $new_hash"

  else
    echo "  Unsupported upstream type: $upstream_type"
  fi
done

echo "--------------------------------------------------"
echo "✅ Custom package check complete."
