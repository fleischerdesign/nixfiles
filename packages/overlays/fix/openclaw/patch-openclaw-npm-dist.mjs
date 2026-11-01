#!/usr/bin/env node
// Compose nix-openclaw's dist-patch phase with the fleet's own dist patches.
//
// The upstream script runs first; each fleet step then targets one shipped
// defect and fails the build when the bundle shape it depends on has moved. A
// release bump therefore cannot silently build an unpatched package.
import { execFileSync } from "node:child_process";

// Each step is its own store path: the entry script is copied into the store on
// its own, so a sibling resolved relative to import.meta.url would not exist.
const steps = [
  process.env.OPENCLAW_UPSTREAM_PATCH_NPM_DIST_SCRIPT,
  process.env.OPENCLAW_SKILL_HARDLINK_PATCH,
  process.env.OPENCLAW_NODE_SPAWN_SOURCE_PATCH,
];

for (const [index, step] of steps.entries()) {
  if (!step) {
    console.error(`openclaw dist patch: step ${index} is unset`);
    process.exit(1);
  }
  execFileSync(process.execPath, [step], { stdio: "inherit", env: process.env });
}
