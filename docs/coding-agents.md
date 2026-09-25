# Coding agents

`features/dev/opencode` installs OpenCode v2 from the official `anomalyco/opencode` `v2` flake package. Its build dependencies retain upstream's lock. The package override omits the upstream shell-completion installation hook because that hook fails during the v2 build. The feature exposes a host-level default model and additional v2 configuration, then writes `~/.config/opencode/opencode.json` for enabled Home Manager users. The package's own update mechanism is disabled because Nix owns its version.

Provider credentials remain in SOPS secret files. `credentialFiles` maps environment variable names to those runtime paths. The `opencode` launcher reads them when the process starts; neither the values nor generated authentication files enter the Nix store. A user with the feature enabled must be allowed to read the referenced files. Interactive provider logins remain OpenCode-owned local state.

`features/dev/openchamber` exposes two optional interfaces on hosts with OpenCode enabled. The web/CLI package is locked to the published `@openchamber/web` npm dependency graph and provides the `openchamber` command. It uses the `opencode` executable on the user's path. The desktop package wraps the official Linux AppImage and provides a desktop launcher. Both packages use the same OpenChamber release version. The desktop release includes its own matching OpenCode executable, as provided upstream.

The workstation and notebook enable both interfaces for the primary Home Manager user. The web interface binds to loopback by default and starts only when invoked with `openchamber`; the desktop interface starts from its launcher. No listener or firewall rule is created by these features.
