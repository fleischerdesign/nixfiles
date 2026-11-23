# Fleet OpenCode Tools

A panel-less built-in extension that ships one OpenCode plugin. The plugin adds
the `fleet_runtime` tool, which reports the runtime host and the session's
working directory. It exists to prove the `contributes.opencodePlugin` path:
OpenChamber lists the folder in the managed OpenCode config while the extension
is enabled, and removing the extension removes the tool.

The plugin is a single self-contained module because OpenCode loads it from a
folder with no installed dependencies. Keep the same rule for any larger
plugin: bundle it before adding it here.
