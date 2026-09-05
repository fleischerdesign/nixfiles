# DeepSeek Harness (dsh) — Agent Instruction Handbook

You are running inside a DeepSeek Harness (dsh) agent environment on a **NixOS** workstation.

## Environment & Filesystem Layout

- **Store & Core Configurations are Immutable (Read-Only):**
  - Core plugins and packages are managed by Nix in `/nix/store` and linked into `~/.dsh/node_modules/`.
  - Do not attempt to write directly to `~/.dsh/node_modules/` or edit `~/.dsh/settings.yaml` in-place (they are store symlinks; writes fail with `EACCES` or `EROFS`).
  - System credentials live in `~/.dsh/.credentials.yaml` (managed via SOPS secrets). Never print, log, or leak these values.

## Self-Improvement & Custom Plugins: The Incubator

When you need to develop, experiment with, or prototype new Cordis plugins, tools, or workflows:

1. **Use the Plugin Incubator:**
   - Location: `~/.dsh/incubator/<plugin-name>/`
   - This directory is completely mutable, local to your workspace, and watched by the runtime.

2. **Incubator Plugin Structure:**
   Every incubator plugin must be a valid NPM/Cordis package:
   - `~/.dsh/incubator/<plugin-name>/package.json`
     ```json
     {
       "name": "<plugin-name>",
       "version": "0.1.0",
       "main": "index.js",
       "dsh": {
         "bundle": {
           "patch": "cordis.patch.yml"
         }
       }
     }
     ```
   - `~/.dsh/incubator/<plugin-name>/index.js` (or `lib/index.js`): Exposes the Cordis plugin or tool implementation.
   - `~/.dsh/incubator/<plugin-name>/cordis.patch.yml` (optional): Defines Cordis insert rows or configurations.

3. **Promoting an Incubated Plugin to Permanent NixOS Infrastructure:**
   Once a prototype is verified and stable, inform the user:
   - "The plugin `<name>` in `~/.dsh/incubator/<name>` is working as expected."
   - You can propose turning it into a declarative Nix package under `/etc/nixos/features/dev/dsh/plugins/<name>/` (`manifest.json` + `package.nix`), so it becomes part of the reproducible Flake across all hosts.

## Core Rules & Safety
- Always review code and dependencies before executing unknown shell scripts.
- Prefer non-destructive, modular designs.
- Report all tool and sandbox limitations transparently to the user.
