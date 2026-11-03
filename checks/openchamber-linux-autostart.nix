# The Linux autostart patch must keep naming the declared launcher and must fail closed when the
# pinned resolver moves. The failure it catches: a future OpenChamber start rewrites the login entry
# with the bare Electron binary, silently dropping the provisioning environment for the next login.
# The positive case against the real package is decided by the desktop derivation's postPatch; this
# fixture proves the resolver contract and the script's fail-closed behaviour on a tiny tree.
{
  pkgs,
  ...
}:
let
  fixture = pkgs.runCommandLocal "openchamber-autostart-fixture" { } ''
    mkdir -p $out/packages/electron
    cat > $out/packages/electron/package.json <<'EOF'
    {"name":"fixture","version":"2.6.0","type":"module"}
    EOF
    cat > $out/packages/electron/linux-autostart.mjs <<'EOF'
    import path from 'node:path';

    export const resolveLinuxLaunchExecutable = ({
      env = process.env,
      execPath = process.execPath,
    } = {}) => {
      const appImage = typeof env.APPIMAGE === "string" ? env.APPIMAGE.trim() : "";
      if (appImage && path.isAbsolute(appImage)) {
        return appImage;
      }
      return execPath;
    };
    EOF
  '';

  patch = ../packages/overlays/fix/openchamber/patch-linux-autostart.mjs;
in
pkgs.runCommandLocal "openchamber-linux-autostart-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    set -euo pipefail

    # Positive: the declared launcher wins over execPath, and an unset override leaves the old
    # behaviour untouched so a host without the launcher does not lose its entry.
    cp -r ${fixture} applied
    chmod -R u+w applied
    (
      cd applied
      node ${patch}
      node --input-type=module -e '
        import { resolveLinuxLaunchExecutable } from "./packages/electron/linux-autostart.mjs";
        const declared = resolveLinuxLaunchExecutable({
          env: { OPENCHAMBER_AUTOSTART_EXEC: "/run/current-system/sw/bin/openchamber-launch" },
          execPath: "/nix/store/raw/openchamber",
        });
        if (declared !== "/run/current-system/sw/bin/openchamber-launch") {
          throw new Error(`override ignored: ''${declared}`);
        }
        const fallback = resolveLinuxLaunchExecutable({
          env: {},
          execPath: "/nix/store/raw/openchamber",
        });
        if (fallback !== "/nix/store/raw/openchamber") {
          throw new Error(`fallback changed: ''${fallback}`);
        }
        const relative = resolveLinuxLaunchExecutable({
          env: { OPENCHAMBER_AUTOSTART_EXEC: "bin/openchamber-launch" },
          execPath: "/nix/store/raw/openchamber",
        });
        if (relative !== "/nix/store/raw/openchamber") {
          throw new Error(`relative override was accepted: ''${relative}`);
        }
      '
      # A second application must not insert the override twice.
      if node ${patch}; then
        echo "patch accepted an already patched source" >&2
        exit 1
      fi
    )

    # A version bump must fail loudly instead of applying an unverified patch.
    cp -r ${fixture} changed
    chmod -R u+w changed
    (
      cd changed
      sed -i 's/"version":"2.6.0"/"version":"9.9.9"/' packages/electron/package.json
      if node ${patch}; then
        echo "patch accepted an unverified upstream version" >&2
        exit 1
      fi
    )

    # A moved resolver must fail loudly as well.
    cp -r ${fixture} moved
    chmod -R u+w moved
    (
      cd moved
      sed -i 's/resolveLinuxLaunchExecutable/resolveLaunchExecutableRenamed/' packages/electron/linux-autostart.mjs
      if node ${patch}; then
        echo "patch accepted a moved resolver" >&2
        exit 1
      fi
    )
    touch $out
  ''
