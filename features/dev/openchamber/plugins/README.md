# Declarative OpenChamber extensions

Each immediate subdirectory is an extension package, discovered automatically. Files in this
folder, including this document, are ignored. Directory names use lowercase letters, digits and
hyphens, starting with a letter.

A package has a `package.json` using the OpenChamber SDK manifest. The manifest is wrapped in the
package envelope, so `openchamber` sits beside `name` and `version`:

```json
{
  "name": "example-panel",
  "version": "0.0.1",
  "openchamber": {
    "apiVersion": 1,
    "contributes": {
      "panel": {
        "id": "openchamber-builtin-example-panel",
        "name": "Example",
        "icon": "apps",
        "entry": "panel/index.html"
      }
    }
  }
}
```

Requirements:

- `version` must be a non-empty semver string; OpenChamber's package inspector rejects a missing
  version. This feature keeps the declared version as-is.
- `openchamber.apiVersion` must be `1`.
- `openchamber.id` must be `openchamber-builtin-<directory-name>`. The older
  `openchamber.contributes.panel.id` is accepted when `openchamber.id` is absent, but the two must
  agree when both exist.
- `openchamber.contributes.panel` is optional. Service-only, background-only, page-only and
  `opencodePlugin`-only extensions are valid and are shipped without a rail panel.
- When a panel is present, `panel.name` must be non-empty and `panel.icon` must be a built-in icon
  name (matching the panel-id pattern) or a relative `.svg` file in the package.
- `panel.entry`, when present, must point at a self-contained HTML file whose local scripts exist.
  Include the built HTML/JavaScript and any runtime assets; dependency installation and arbitrary
  build scripts are not run for extension directories.
- Declared capabilities are granted automatically to built-ins, but normal capability, path,
  credential-target and enabled-state checks still apply. Built-in status is not extra authority.
- `package.json` and every declared entry must be shipped prebuilt. The feature copies the directory
  as-is; it does not run dependency installation or plugin build scripts. Build TypeScript and
  service/OpenCode-plugin bundles before committing the package.

The Nix build merges this directory into the app's own built-in registry. An ID or directory
collision with an upstream built-in fails the build instead of silently replacing it. The merged
packages are validated with OpenChamber's own inspector during the build.

After a NixOS switch and an application restart, these extensions appear as Built-in. Their declared
permissions are trusted as part of the system configuration. They can be disabled in OpenChamber;
their data and disabled state remain writable and survive upgrades. Removing a directory removes
its extension from the next application build.

Use OpenChamber's `/new-extension` and Settings → Extensions to develop and install runtime
extensions. Folder installs run from the writable development folder and can be edited and reloaded.
These installs keep OpenChamber's normal permission prompts, updates and removal. This feature does
not replace `extensions.json` or the writable extension directories.

To promote an extension, copy its package and built assets into a new subdirectory here, change its
panel ID to the reserved built-in ID above, bump its `version`, and add the files to Git. Switch and
restart OpenChamber. The new ID has separate extension storage; export or migrate any
extension-specific data before removing the development install. Secrets and generated
`node_modules` never belong here.

These are OpenChamber extensions, which may themselves contribute an OpenCode plugin. Bare OpenCode
plugins belong in OpenChamber's Plugins settings or in an extension's `opencodePlugin` contribution.
The `fleet-session-journal` package is the panel-less fixture: it ships only a local service and a
`sessionEvents` subscription.
