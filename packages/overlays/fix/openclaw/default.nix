# packages/overlays/fix/openclaw/default.nix
# Upstream OpenClaw enforces strict hardlink checks (`hardlinks: "reject"` / `stat.nlink > 1`)
# when loading skills (`bundle.ts` / `selection-*.mjs`) and through `@openclaw/fs-safe`.
# On NixOS with `nix.settings.auto-optimise-store = true`, files in /nix/store (such as
# plugin SKILL.md files) are deduplicated into hardlinks (nlink > 1), causing OpenClaw
# to crash on worker turn initialization with `hardlink: hardlinked path not allowed | INVALID_BUNDLE`.
#
# It also patches the File Transfer plugin's directory fetch: upstream spawns the literal
# `/usr/bin/tar`, an FHS path that does not exist on NixOS (only `/usr/bin/env` is present), so
# `dir.fetch` fails with the misleading `READ_ERROR: tar command failed` even though GNU tar is in
# the node host's PATH. Every patch that must land is checked afterwards, so an upstream rename
# fails the build instead of silently disabling the fix.
#
# This overlay patches the compiled dist modules in openclaw-gateway,
# and rebuilds the openclaw battery wrapper so both gateway and companion nodes inherit the fix.
_final: prev:
let
  patchedGateway = prev.openclaw-gateway.overrideAttrs (oldAttrs: {
    installPhase =
      (oldAttrs.installPhase or "")
      + "\n"
      + ''
        ${prev.nodejs_24}/bin/node -e '
          const fs = require("fs");
          const path = require("path");

          // 1. Patch @openclaw/fs-safe in node_modules to relax hardlink rejection
          const fsSafePath = process.env.out + "/lib/node_modules/@openclaw/fs-safe/dist/root-impl.js";
          if (fs.existsSync(fsSafePath)) {
            let c = fs.readFileSync(fsSafePath, "utf8");
            c = c.replace(
              /if \(options\?\.hardlinks === "reject" && stat\.nlink > 1\) \{\s*throw hardlinkedPathNotAllowedError\(\);\s*\}/g,
              "/* hardlinks allowed in Nix store */"
            );
            c = c.replace(
              /if \(options\?\.hardlinks === "reject" && realStat\.nlink > 1n\) \{\s*throw hardlinkedPathNotAllowedError\(\);\s*\}/g,
              "/* hardlinks allowed in Nix store */"
            );
            c = c.replace(
              /if \(params\.hardlinks !== "allow" && opened\.stat\.nlink > 1\) \{\s*await opened\.handle\.close\(\)\.catch\(\(\) => \{\s*\}\);\s*throw hardlinkedPathNotAllowedError\(\);\s*\}/g,
              "/* hardlinks allowed in Nix store */"
            );
            fs.writeFileSync(fsSafePath, c);
          }

          // 2. Patch openclaw dist selection-*.mjs to allow hardlinks in readSkillBundleTree
          const distDir = process.env.out + "/lib/node_modules/openclaw/dist";
          if (fs.existsSync(distDir)) {
            for (const f of fs.readdirSync(distDir)) {
              if (f.startsWith("selection-") && f.endsWith(".mjs")) {
                const full = path.join(distDir, f);
                let c = fs.readFileSync(full, "utf8");
                if (c.includes("hardlinks: \"reject\"")) {
                  c = c.replace(/hardlinks: "reject"/g, "hardlinks: \"allow\"");
                  fs.writeFileSync(full, c);
                }
              }
              // 3. Patch verified-inference-*.mjs to allow symlink entries in runtime artifact scan and hash
              if (f.startsWith("verified-inference-") && f.endsWith(".mjs")) {
                const full = path.join(distDir, f);
                let c = fs.readFileSync(full, "utf8");
                if (c.includes("if (entry.kind !== \"file\") throw new Error(`plugin runtime artifact contains unsupported ''${entry.kind} entry`);")) {
                  c = c.replace(
                    "if (entry.kind !== \"file\") throw new Error(`plugin runtime artifact contains unsupported ''${entry.kind} entry`);",
                    "if (entry.kind !== \"file\" && entry.kind !== \"symlink\") throw new Error(`plugin runtime artifact contains unsupported ''${entry.kind} entry`);"
                  );
                }
                if (c.includes("rejectHardlinks: false\n\t});") || c.includes("rejectHardlinks: false\n  });") || c.includes("rejectHardlinks: false\r\n\t});")) {
                  c = c.replace(/rejectHardlinks:\s*false/g, "rejectHardlinks: false,\n\t\trejectSymlinks: false");
                }
                fs.writeFileSync(full, c);
              }
            }
          }

          // 4. Patch dir-fetch-*.mjs: upstream spawns the literal "/usr/bin/tar", which does not
          //    exist on NixOS. Resolve "tar" through PATH instead (the node host PATH carries
          //    gnutar). Both the patch and the absence of the old string are asserted, so an
          //    upstream rename cannot turn this into a silent no-op.
          const dirFetchFiles = fs.existsSync(distDir)
            ? fs.readdirSync(distDir).filter((f) => f.startsWith("dir-fetch-") && f.endsWith(".mjs"))
            : [];
          let dirFetchPatched = 0;
          for (const f of dirFetchFiles) {
            const full = path.join(distDir, f);
            let c = fs.readFileSync(full, "utf8");
            if (c.includes("/usr/bin/tar")) {
              c = c.split("/usr/bin/tar").join("tar");
              fs.writeFileSync(full, c);
              dirFetchPatched += 1;
            }
          }
          if (dirFetchPatched === 0) {
            console.error("openclaw overlay: no dir-fetch module with the hard-coded \"/usr/bin/tar\" was found - the PATH patch would be a no-op");
            process.exit(1);
          }
          const leftovers = dirFetchFiles.filter((f) =>
            fs.readFileSync(path.join(distDir, f), "utf8").includes("/usr/bin/tar")
          );
          if (leftovers.length > 0) {
            console.error("openclaw overlay: /usr/bin/tar still present in " + leftovers.join(", "));
            process.exit(1);
          }
        '
      '';
  });

  patchedOpenclaw = prev.openclaw.override {
    openclaw-gateway = patchedGateway;
  };
in
{
  openclaw-gateway = patchedGateway;
  openclaw = patchedOpenclaw;
}
