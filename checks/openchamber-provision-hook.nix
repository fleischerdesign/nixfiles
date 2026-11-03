# The desktop provisioning hook must be present before the single-instance lock in the pinned
# upstream source, and the patch must fail instead of silently accepting a moved version or insertion
# point. Without the first property `app.relaunch()` starts the app without reconciling its token;
# without the second a bump could ship an unpatched desktop while every gate stays green.
{
  pkgs,
  inputs,
  ...
}:
pkgs.runCommandLocal "openchamber-provision-hook-check"
  {
    nativeBuildInputs = [ pkgs.nodejs_22 ];
  }
  ''
    cp -r ${inputs.openchamber.outPath} source
    chmod -R u+w source
    (
      cd source
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
    cp -r ${inputs.openchamber.outPath} changed
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
    cp -r ${inputs.openchamber.outPath} moved
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
