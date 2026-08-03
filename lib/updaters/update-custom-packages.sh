#!/usr/bin/env bash
# lib/updaters/update-custom-packages.sh
# Universal auto-update engine for custom packages.
# Scans packages/custom/ and features/ for manifest.json files and updates
# them when upstream releases change.
#
# Supported upstream types:
#   github-release   — GitHub Release with AppImage asset
#   github-source    — GitHub Release, rebuild from source tarball
#   github-rev       — Pinned to a git commit, tracks default branch HEAD
#   pypi             — PyPI package, single or multi-package manifests

set -euo pipefail

if [ -d "$PWD/packages/custom" ]; then
  REPO_ROOT="$PWD"
elif [ -d "/etc/nixos/packages/custom" ]; then
  REPO_ROOT="/etc/nixos"
else
  REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || pwd)"
fi
CUSTOM_PKGS_DIR="$REPO_ROOT/packages/custom"
TARGET_PKG="${1:-all}"

if [ ! -d "$CUSTOM_PKGS_DIR" ]; then
  echo "No packages/custom directory found at $CUSTOM_PKGS_DIR"
  exit 0
fi

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

gh_api() {
  # Make an authenticated or unauthenticated GitHub API call.
  local url="$1"
  if [ -n "${GITHUB_TOKEN:-}" ]; then
    curl -sf -H "Authorization: token $GITHUB_TOKEN" "$url"
  else
    curl -sf "$url"
  fi
}

pypi_api() {
  # Fetch PyPI package JSON metadata.
  local pkg="$1"
  curl -sf "https://pypi.org/pypi/${pkg}/json"
}

strip_v() {
  sed 's/^v//'
}

echo "🔍 Checking custom packages for upstream updates..."

MANIFEST_PATHS=()
while IFS= read -r -d '' mp; do
  MANIFEST_PATHS+=("$mp")
done < <(find "$REPO_ROOT/packages/custom" "$REPO_ROOT/features" -name manifest.json -print0 2>/dev/null)

# ---------------------------------------------------------------------------
# Per-manifest update logic
# ---------------------------------------------------------------------------

for manifest_path in "${MANIFEST_PATHS[@]}"; do
  [ -f "$manifest_path" ] || continue

  pkg_dir="$(dirname "$manifest_path")"
  pkg_name="$(basename "$pkg_dir")"

  if [ "$TARGET_PKG" != "all" ] && [ "$TARGET_PKG" != "$pkg_name" ]; then
    continue
  fi

  echo "--------------------------------------------------"
  echo "📦 Processing $pkg_name..."

  upstream_type="$(jq -r '.upstream.type // "none"' "$manifest_path")"

  # =========================================================================
  # github-release — AppImage asset from GitHub Release
  # =========================================================================

  if [ "$upstream_type" = "github-release" ]; then
    owner="$(jq -r '.upstream.owner' "$manifest_path")"
    repo="$(jq -r '.upstream.repo' "$manifest_path")"
    current_version="$(jq -r '.version' "$manifest_path")"

    echo "  Current version: $current_version"
    echo "  Checking GitHub upstream: $owner/$repo..."

    RELEASE_JSON="$(gh_api "https://api.github.com/repos/$owner/$repo/releases/latest")" || {
      echo "  ⚠️ Could not fetch latest release for $owner/$repo"
      continue
    }

    latest_tag="$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty' | strip_v)"

    if [ -z "$latest_tag" ]; then
      echo "  ⚠️ Could not parse latest release tag"
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
    echo "  ✨ Updated $pkg_name to v$latest_tag"

  # =========================================================================
  # github-source — source tarball from GitHub Release, built from source
  # =========================================================================

  elif [ "$upstream_type" = "github-source" ]; then
    owner="$(jq -r '.upstream.owner' "$manifest_path")"
    repo="$(jq -r '.upstream.repo' "$manifest_path")"
    current_version="$(jq -r '.version' "$manifest_path")"

    echo "  Current version: $current_version"
    echo "  Checking GitHub upstream: $owner/$repo..."

    RELEASE_JSON="$(gh_api "https://api.github.com/repos/$owner/$repo/releases/latest")" || {
      echo "  ⚠️ Could not fetch latest release for $owner/$repo"
      continue
    }

    latest_tag="$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty' | strip_v)"

    if [ -z "$latest_tag" ]; then
      echo "  ⚠️ Could not parse latest release tag"
      continue
    fi

    if [ "$latest_tag" = "$current_version" ]; then
      echo "  ✅ $pkg_name is already up to date (v$current_version)."
      continue
    fi

    echo "  🎉 New version available: v$latest_tag (current: v$current_version)"

    # Fetch source tarball and compute SRI hash.
    tarball_url="$(echo "$RELEASE_JSON" | jq -r '.tarball_url // empty')"
    if [ -z "$tarball_url" ]; then
      echo "  ⚠️ No tarball_url in release, falling back to archive URL"
      tarball_url="https://github.com/$owner/$repo/archive/refs/tags/v$latest_tag.tar.gz"
    fi

    echo "  Downloading and hashing source tarball..."
    new_src_hash="$(nix store prefetch-file --unpack "$tarball_url" --json | jq -r '.hash')"

    if [ -z "$new_src_hash" ] || [ "$new_src_hash" = "null" ]; then
      echo "  ❌ Failed to calculate source hash"
      continue
    fi

    # Build-time hashes (cargoHash, etc.) are reset to empty so the next
    # nix-build will reveal the correct value via hash mismatch.
    tmp_manifest="$(mktemp)"
    jq --arg ver "$latest_tag" \
       --arg src_hash "$new_src_hash" \
       '.version = $ver | .srcHash = $src_hash | .cargoHash = ""' \
       "$manifest_path" > "$tmp_manifest"

    mv "$tmp_manifest" "$manifest_path"
    echo "  ✨ Updated $pkg_name to v$latest_tag (srcHash, cargoHash needs manual update)"

  # =========================================================================
  # github-rev — pinned to a commit, tracks default branch HEAD
  # =========================================================================

  elif [ "$upstream_type" = "github-rev" ]; then
    owner="$(jq -r '.upstream.owner' "$manifest_path")"
    repo="$(jq -r '.upstream.repo' "$manifest_path")"
    current_rev="$(jq -r '.rev // empty' "$manifest_path")"
    current_version="$(jq -r '.version // empty' "$manifest_path")"

    echo "  Current rev: ${current_rev:0:12}..."
    echo "  Checking GitHub upstream: $owner/$repo..."

    # Fetch default branch name.
    default_branch="$(gh_api "https://api.github.com/repos/$owner/$repo" | jq -r '.default_branch // "main"')"

    # Fetch latest commit on default branch.
    latest_commit="$(gh_api "https://api.github.com/repos/$owner/$repo/commits/$default_branch" | jq -r '.sha // empty')" || {
      echo "  ⚠️ Could not fetch latest commit for $owner/$repo"
      continue
    }

    if [ -z "$latest_commit" ]; then
      echo "  ⚠️ Could not parse latest commit SHA"
      continue
    fi

    if [ "$latest_commit" = "$current_rev" ]; then
      echo "  ✅ $pkg_name is already at the latest commit."
      continue
    fi

    echo "  🎉 New commit: ${latest_commit:0:12} (current: ${current_rev:0:12})"

    # Fetch source tarball at the new commit and compute SRI hash.
    tarball_url="https://github.com/$owner/$repo/archive/${latest_commit}.tar.gz"
    echo "  Downloading and hashing source tarball..."

    new_src_hash="$(nix store prefetch-file --unpack "$tarball_url" --json | jq -r '.hash')"

    if [ -z "$new_src_hash" ] || [ "$new_src_hash" = "null" ]; then
      echo "  ❌ Failed to calculate source hash"
      continue
    fi

    tmp_manifest="$(mktemp)"
    jq --arg rev "$latest_commit" \
       --arg src_hash "$new_src_hash" \
       '.rev = $rev | .srcHash = $src_hash' \
       "$manifest_path" > "$tmp_manifest"
    mv "$tmp_manifest" "$manifest_path"

    # Auto-inspect source tarball for version updates & npmDepsHash
    tmp_src="$(mktemp -d)"
    if curl -sfL "$tarball_url" | tar -xz -C "$tmp_src" --strip-components=1 2>/dev/null; then
      # 1. Check for version in pyproject.toml or package.json
      extracted_version=""
      if [ -f "$tmp_src/pyproject.toml" ]; then
        extracted_version="$(python3 -c "import tomllib; print(tomllib.load(open('$tmp_src/pyproject.toml', 'rb')).get('project', {}).get('version', ''))" 2>/dev/null || true)"
        if [ -z "$extracted_version" ]; then
          extracted_version="$(grep -m1 '^version' "$tmp_src/pyproject.toml" 2>/dev/null | cut -d'"' -f2 || true)"
        fi
      elif [ -f "$tmp_src/package.json" ]; then
        extracted_version="$(jq -r '.version // empty' "$tmp_src/package.json" 2>/dev/null || true)"
      fi

      if [ -n "$extracted_version" ] && [ "$(jq -r '.version // empty' "$manifest_path")" != "" ]; then
        echo "  🔍 Extracted version from source metadata: $extracted_version"
        tmp_man="$(mktemp)"
        jq --arg ver "$extracted_version" '.version = $ver' "$manifest_path" > "$tmp_man"
        mv "$tmp_man" "$manifest_path"
      fi

      # 2. Auto-calculate npmDepsHash if field exists
      if jq -e 'has("npmDepsHash")' "$manifest_path" >/dev/null 2>&1; then
        if [ -f "$tmp_src/package-lock.json" ]; then
          echo "  📦 Calculating npmDepsHash via prefetch-npm-deps..."
          new_npm_hash="$( (cd "$tmp_src" && nix run nixpkgs#prefetch-npm-deps -- package-lock.json 2>/dev/null) | tail -n 1 || true)"
          if [[ "$new_npm_hash" == sha256-* ]]; then
            echo "  ✨ Auto-calculated npmDepsHash: $new_npm_hash"
            tmp_man="$(mktemp)"
            jq --arg hash "$new_npm_hash" '.npmDepsHash = $hash' "$manifest_path" > "$tmp_man"
            mv "$tmp_man" "$manifest_path"
          else
            echo "  ⚠️ Could not calculate npmDepsHash automatically, setting empty"
            tmp_man="$(mktemp)"
            jq '.npmDepsHash = ""' "$manifest_path" > "$tmp_man"
            mv "$tmp_man" "$manifest_path"
          fi
        fi
      fi
    fi
    rm -rf "$tmp_src"

    echo "  ✨ Updated $pkg_name to commit ${latest_commit:0:12}"

  # =========================================================================
  # pypi — Python package from PyPI, supports single and multi-package manifests
  # =========================================================================

  elif [ "$upstream_type" = "pypi" ]; then
    manif="$(cat "$manifest_path")"

    # Distinguish single vs multi-package manifest.
    has_packages="$(echo "$manif" | jq -r '.upstream.packages // empty')"

    if [ -n "$has_packages" ]; then
      # -------------------------------------------------------------------
      # Multi-package pypi manifest
      # -------------------------------------------------------------------
      echo "  (multi-package pypi manifest)"

      updated=0
      pkg_keys="$(echo "$manif" | jq -r '.upstream.packages | keys[]')"

      for key in $pkg_keys; do
        pypi_name="$(echo "$manif" | jq -r ".upstream.packages.\"$key\"")"
        # Derive the version field name from the key: e.g. "memory" → "memoryVersion"
        version_field="${key}Version"
        hash_field="${key}Hash"
        current_version="$(echo "$manif" | jq -r ".$version_field // empty")"

        echo "  📦 $key ($pypi_name) — current: $current_version"

        PYPI_JSON="$(pypi_api "$pypi_name")" || {
          echo "    ⚠️ Could not fetch PyPI metadata for $pypi_name"
          continue
        }

        latest_version="$(echo "$PYPI_JSON" | jq -r '.info.version // empty')"
        if [ -z "$latest_version" ]; then
          echo "    ⚠️ Could not parse latest version"
          continue
        fi

        if [ "$latest_version" = "$current_version" ]; then
          echo "    ✅ Already up to date ($latest_version)."
          continue
        fi

        echo "    🎉 New version: $latest_version"

        source_url="$(echo "$PYPI_JSON" | jq -r '.urls[] | select(.packagetype=="sdist").url // empty' | head -n 1)"
        if [ -z "$source_url" ]; then
          source_url="https://pypi.org/packages/source/${pypi_name:0:1}/${pypi_name}/${pypi_name//-/_}-${latest_version}.tar.gz"
        fi

        new_hash="$(nix store prefetch-file --unpack "$source_url" --json | jq -r '.hash')"
        if [ -z "$new_hash" ] || [ "$new_hash" = "null" ]; then
          echo "    ❌ Failed to calculate hash"
          continue
        fi

        manif="$(echo "$manif" | jq \
          --arg ver "$latest_version" \
          --arg hash "$new_hash" \
          ".$version_field = \$ver | .$hash_field = \$hash")"
        updated=1
        echo "    ✨ Updated $key to $latest_version"
      done

      if [ "$updated" -eq 1 ]; then
        echo "$manif" > "$manifest_path"
        echo "  ✨ Multi-package manifest updated."
      fi

    else
      # -------------------------------------------------------------------
      # Single-package pypi manifest
      # -------------------------------------------------------------------
      pypi_pkg="$(echo "$manif" | jq -r '.upstream.package // empty')"
      current_version="$(echo "$manif" | jq -r '.version // empty')"

      echo "  📦 $pypi_pkg — current: $current_version"

      PYPI_JSON="$(pypi_api "$pypi_pkg")" || {
        echo "  ⚠️ Could not fetch PyPI metadata for $pypi_pkg"
        continue
      }

      latest_version="$(echo "$PYPI_JSON" | jq -r '.info.version // empty')"
      if [ -z "$latest_version" ]; then
        echo "  ⚠️ Could not parse latest version"
        continue
      fi

      if [ "$latest_version" = "$current_version" ]; then
        echo "  ✅ $pkg_name is already up to date ($latest_version)."
        continue
      fi

      echo "  🎉 New version: $latest_version"

      source_url="$(echo "$PYPI_JSON" | jq -r '.urls[] | select(.packagetype=="sdist").url // empty' | head -n 1)"
      if [ -z "$source_url" ]; then
        source_url="https://pypi.org/packages/source/${pypi_pkg:0:1}/${pypi_pkg}/${pypi_pkg//-/_}-${latest_version}.tar.gz"
      fi

      new_hash="$(nix store prefetch-file --unpack "$source_url" --json | jq -r '.hash')"
      if [ -z "$new_hash" ] || [ "$new_hash" = "null" ]; then
        echo "  ❌ Failed to calculate hash"
        continue
      fi

      tmp_manifest="$(mktemp)"
      jq --arg ver "$latest_version" \
         --arg hash "$new_hash" \
         '.version = $ver | .srcHash = $hash' \
         "$manifest_path" > "$tmp_manifest"

      mv "$tmp_manifest" "$manifest_path"
      echo "  ✨ Updated $pkg_name to $latest_version"
    fi

  # =========================================================================
  # obsidian-plugin — GitHub Release assets (main.js, manifest.json, styles.css)
  # =========================================================================

  elif [ "$upstream_type" = "obsidian-plugin" ]; then
    owner="$(jq -r '.upstream.owner' "$manifest_path")"
    repo="$(jq -r '.upstream.repo' "$manifest_path")"
    current_version="$(jq -r '.version' "$manifest_path")"

    echo "  Current version: $current_version"
    echo "  Checking GitHub upstream: $owner/$repo..."

    RELEASE_JSON="$(gh_api "https://api.github.com/repos/$owner/$repo/releases/latest")" || {
      echo "  ⚠️ Could not fetch latest release for $owner/$repo"
      continue
    }

    latest_tag="$(echo "$RELEASE_JSON" | jq -r '.tag_name // empty' | strip_v)"

    if [ -z "$latest_tag" ]; then
      echo "  ⚠️ Could not parse latest release tag"
      continue
    fi

    if [ "$latest_tag" = "$current_version" ]; then
      echo "  ✅ $pkg_name is already up to date (v$current_version)."
      continue
    fi

    echo "  🎉 New version available: v$latest_tag (current: v$current_version)"

    tag_ver="$latest_tag"
    if echo "$RELEASE_JSON" | jq -r '.tag_name' | grep -q '^v'; then
      tag_ver="v$latest_tag"
    fi

    main_url="https://github.com/$owner/$repo/releases/download/$tag_ver/main.js"
    manifest_url="https://github.com/$owner/$repo/releases/download/$tag_ver/manifest.json"
    styles_url="https://github.com/$owner/$repo/releases/download/$tag_ver/styles.css"

    echo "  Downloading and hashing plugin assets..."
    main_hash="$(nix-prefetch-url "$main_url" 2>/dev/null || true)"
    manifest_hash="$(nix-prefetch-url "$manifest_url" 2>/dev/null || true)"
    styles_hash="$(nix-prefetch-url "$styles_url" 2>/dev/null || true)"

    if [ -z "$main_hash" ] || [ -z "$manifest_hash" ]; then
      echo "  ❌ Failed to calculate hashes for plugin assets"
      continue
    fi

    tmp_manifest="$(mktemp)"
    jq --arg ver "$latest_tag" \
       --arg main "$main_hash" \
       --arg manifest "$manifest_hash" \
       --arg styles "${styles_hash:-}" \
       '.version = $ver | .mainHash = $main | .manifestHash = $manifest | .stylesHash = $styles' \
       "$manifest_path" > "$tmp_manifest"

    mv "$tmp_manifest" "$manifest_path"
    echo "  ✨ Updated $pkg_name to v$latest_tag"

  # =========================================================================
  # Unknown type
  # =========================================================================

  else
    echo "  ⚠️ Unsupported upstream type: $upstream_type"
  fi
done

echo "--------------------------------------------------"
echo "✅ Custom package check complete."
