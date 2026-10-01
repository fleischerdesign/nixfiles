# Package updates

`.github/workflows/update.yml` updates `flake.lock`, runs the manifest updater, checks the flake
and builds every inventory host before committing the updated lock and package metadata. A failed
preparation or host build prevents publication. Manifests and vendored npm lockfiles under
`packages/custom` travel with the flake lock through the workflow artifacts.

`nix run .#update-custom-packages` discovers manifests under `packages/custom` and `features`.
Pass a directory name to update only that package, for example:

```fish
nix run .#update-custom-packages -- opencode
```

Release, revision, PyPI, npm and Obsidian manifests select their upstream using `upstream.type`.
Source-package updates measure fixed-output hashes from the package's own derivations and verify
them with a second build. A failed source-package refresh restores its previous manifest.

## Flake-managed packages

`upstream.type = "flake-package"` leaves source selection to `flake.lock`. Its manifest declares
`upstream.package`, the flake package output, and `upstream.dependencyAttributes`, a map of logical
dependency names to fixed-output derivation attributes on that package. No provider-specific API,
release lookup or dependency installer is needed in this update handler.

The package consumes `dependencyHashes.<system>.<name>`, using an empty hash when bootstrapping
a platform without metadata (a normal build then fails with a hash mismatch). The updater records
`dependencyDerivations.<system>.<name>`, the derivation path evaluated with an empty dependency hash.
This fingerprints the source, toolchain, platform and recipe without depending on the measured hash.
Changed inputs trigger measurement and verification; unchanged inputs preserve their existing hash.
Any failure or interruption restores the entire previous manifest. Errors remain visible on stderr.
Hashes are measured for the package's build platform, not copied between platforms.

OpenCode uses this schema in `packages/custom/opencode/manifest.json`. Its source revision comes
from the OpenCode flake input; its dependency build uses the fleet's Bun package. The overlay checks
that Bun matches the upstream `packageManager` requirement. An unsupported Bun version fails loudly
rather than changing that requirement or accepting an unverified dependency tree.
