# packages/overlays/fix/openclaw/default.nix
# Upstream OpenClaw enforces strict hardlink checks (`hardlinks: "reject"` / `stat.nlink > 1`)
# when loading skills (`bundle.ts` / `selection-*.mjs`) and through `@openclaw/fs-safe`.
# On NixOS with `nix.settings.auto-optimise-store = true`, files in /nix/store (such as
# plugin SKILL.md files) are deduplicated into hardlinks (nlink > 1), causing OpenClaw
# to crash on worker turn initialization with `hardlink: hardlinked path not allowed | INVALID_BUNDLE`.
#
# This overlay patches the compiled dist modules in openclaw-gateway to allow hardlinks,
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
