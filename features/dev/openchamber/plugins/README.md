# Declarative OpenChamber extensions

Each immediate subdirectory is an extension package, discovered automatically. Files in this
folder, including this document, are ignored. Directory names use lowercase letters, digits and
hyphens, starting with a letter.

A package has a `package.json` using the OpenChamber SDK manifest. Its
`openchamber.contributes.panel.id` must be `openchamber-builtin-<directory-name>`. Include its built
HTML/JavaScript and other runtime assets: the package is copied into the application and validated
with OpenChamber's own inspector during the build. Dependency installation and arbitrary build
scripts are not run for extension directories.

After a NixOS switch and an application restart, these extensions appear as Built-in. Their declared
permissions are trusted as part of the system configuration. They can be disabled in OpenChamber;
their data and disabled state remain writable and survive upgrades. Removing a directory removes
its extension from the next application build.

Use OpenChamber's `/new-extension` and Settings → Extensions to develop and install runtime
extensions. Folder installs run from the writable development folder and can be edited and reloaded.
These installs keep OpenChamber's normal permission prompts, updates and removal. This feature does
not replace `extensions.json` or the writable extension directories.

To promote an extension, copy its package and built assets into a new subdirectory here, change its
panel ID to the reserved built-in ID above, and add the files to Git. Switch and restart OpenChamber.
The new ID has separate extension storage; export or migrate any extension-specific data before
removing the development install. Secrets and generated `node_modules` never belong here.

These are OpenChamber extensions, which may themselves contribute an OpenCode plugin. Bare OpenCode
plugins belong in OpenChamber's Plugins settings or in an extension's `opencodePlugin` contribution.
