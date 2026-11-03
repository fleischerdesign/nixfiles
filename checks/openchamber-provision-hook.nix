# The provisioning patch must fail loudly instead of silently accepting a moved version or insertion
# point. The positive case - that it applies exactly once to the pinned upstream entry - belongs to
# the desktop derivation's postPatch and is decided by that build; this fixture proves only the
# script's fail-closed behaviour, on a tiny two-file tree instead of a 103 MB source copy.
{
  pkgs,
  ...
}:
let
  fixture = pkgs.runCommandLocal "openchamber-provision-hook-fixture" { } ''
    mkdir -p $out/packages/electron
    cat > $out/packages/electron/package.json <<'EOF'
    {"name":"fixture","version":"2.6.0"}
    EOF
    cat > $out/packages/electron/entry.mjs <<'EOF'
    import { app, protocol } from 'electron';

    if (!app.requestSingleInstanceLock()) {
      app.quit();
    }
    EOF
  '';
in
pkgs.runCommandLocal "openchamber-provision-hook-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    cp -r ${fixture} patched
    chmod -R u+w patched
    (
      cd patched
      node ${../packages/overlays/fix/openchamber/patch-entry-provision-hook.mjs}
      node --check packages/electron/entry.mjs
      node -e '
        const fs = require("node:fs");
        const source = fs.readFileSync("packages/electron/entry.mjs", "utf8");
        const hook = source.indexOf("__openchamberProvisionHook");
        const lock = source.indexOf("if (!app.requestSingleInstanceLock()) {");
        if (hook < 0) throw new Error("provisioning hook missing");
        if (lock < 0) throw new Error("single-instance lock missing");
        if (!(hook < lock)) throw new Error("provisioning hook is not before the single-instance lock");
        if ((source.match(/__openchamberProvisionHook/g) || []).length !== 3) {
          throw new Error("hook declaration/use count changed");
        }
      '
    )

    # A version bump must fail loudly, not apply an unverified patch.
    cp -r ${fixture} changed
    chmod -R u+w changed
    (
      cd changed
      node -e '
        const fs = require("node:fs");
        const file = "packages/electron/package.json";
        const pkg = JSON.parse(fs.readFileSync(file, "utf8"));
        pkg.version = "9.9.9";
        fs.writeFileSync(file, JSON.stringify(pkg, null, 2));
      '
      if node ${../packages/overlays/fix/openchamber/patch-entry-provision-hook.mjs}; then
        echo "patch accepted an unverified upstream version" >&2
        exit 1
      fi
    )

    # A moved lock line must fail loudly as well.
    cp -r ${fixture} moved
    chmod -R u+w moved
    (
      cd moved
      sed -i 's/app.requestSingleInstanceLock()/app.requestSingleInstanceLockRenamed()/' packages/electron/entry.mjs
      if node ${../packages/overlays/fix/openchamber/patch-entry-provision-hook.mjs}; then
        echo "patch accepted a moved insertion point" >&2
        exit 1
      fi
    )
    touch $out
  ''
