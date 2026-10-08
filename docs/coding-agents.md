# Coding agents

## ChatGPT and Codex

The personal-computer role enables `features/desktop/chatgpt`, `features/dev/codex` and
`features/dev/opencodex`. Each feature has a separate Home Manager enable switch; Philipp selects
all three in `user/philipp/codex.nix`. Server roles do not install these applications.

`packages/custom/chatgpt-linux` packages the official, versioned OpenAI Linux archive. It preserves
the bundled Electron application, Codex runtime, Node runtime and native modules, patches their
Linux dependencies, and installs upstream's desktop entry and icon. The launcher passes
`--ozone-platform=wayland` unconditionally. The `codex://` handler belongs to ChatGPT; browser HTTP
and HTTPS defaults still belong to the graphical profile. Nixpkgs' `chatgpt` package is a separate
macOS package and is not used here. The Linux preview does not support every feature of the other
platforms; in particular, OpenAI documents Computer Use as unavailable on Linux.

The Codex feature installs the pinned Nixpkgs CLI and adds the official `openai.chatgpt` extension
when the user's editor is enabled. The desktop app keeps its upstream-bundled Codex runtime; its
version can differ from the separately packaged CLI. Both use the same user-owned Codex home.
`packages/overlays/fix/codex-editor` patches the extension's native voice helper and bundled libraries
while retaining its own Codex runtime and the extension version pinned by the marketplace input.

`packages/custom/opencodex` packages upstream's compiled Linux release with its adjacent dashboard
and keyring module. Home Manager owns `opencodex-proxy.service`; `ocx service install`, `ocx update`
and the optional Codex shim are not part of this installation. The service starts with the user
manager, reads the declared credential files, and requires `ocx ready` to succeed within 45 seconds.
It initializes upstream's platform-neutral `service-state.json` when absent, naming the same Codex
and proxy homes as the systemd unit and the stable Home Manager profile launcher. Upstream's
ownership checks require both the registration and this record. Existing records are preserved;
a conflicting or malformed record fails upstream's readiness check.
Missing secrets and failed readiness fail the unit. Logs are available through
`journalctl --user -u opencodex-proxy`. The OpenCodex desktop launcher opens the dashboard through
`ocx gui`.

`CODEX_HOME` is `~/.codex`; `OPENCODEX_HOME` is `~/.opencodex`. These paths are shared by the service
and interactive clients. Neither directory is managed as an immutable Home Manager file. On a new
profile, the service creates a private configuration with OpenAI forwarding to the caller's ChatGPT
login, the user's initial provider definitions, and Claude interception and Codex shims disabled.
Philipp's initial provider is OpenCode Go; its key is an environment reference to
the same runtime secret file OpenCode uses. Existing profiles are preserved and edited through the
dashboard. Changes to the initial definitions only affect new profiles.

The proxy binds to `127.0.0.1` on the declared port, default 10100. An existing configuration with
another bind address fails the service's startup check. No firewall publication is created. Provider
selection and credentials remain runtime state; a model catalog entry does not prove model access.
ChatGPT sign-in and live provider access must be completed and verified by the user. This integration
routes Codex in the desktop app and the CLI; ordinary ChatGPT chats use their own connection.

To inspect the integration after activation:

```fish
systemctl --user status opencodex-proxy
ocx ready --json
ocx doctor
codex
```

Expect readiness to report `ready`, and `/status` in Codex to show the selected model. Verify a real
provider request in the dashboard's request log, including its intended upstream. Streaming,
tool execution and follow-up turns must succeed in both clients before relying on a provider.

`checks.codex-proxy` verifies the packaged keyring and embedded runtimes. The local integration
fixture can be run with `python3 checks/codex-proxy.py (command -v ocx)` in fish under a test account
without an installed OpenCodex service. The fixture refuses a live service registration, whose
ownership guard rejects the foreign test homes. It starts an isolated
proxy and a credential-checked HTTP fixture, then verifies routing, tool translation and a streamed
follow-up without using a live provider. It runs outside the Nix build sandbox because upstream's
Codex write coordinator requires a root-owned `/tmp`. Live model access remains a separate check.

## OpenCode

`features/dev/opencode` installs OpenCode v2 from the official `anomalyco/opencode` `v2` flake package. Its build dependencies retain upstream's lock, except Bun: the build uses the fleet's Bun package only when its version matches OpenCode's `packageManager` requirement. The Bun-specific `node_modules` output hash is pinned alongside the override and must be refreshed when the OpenCode input changes. The package override omits the upstream shell-completion installation hook because that hook fails during the v2 build. The feature exposes a host-level default model and additional v2 configuration, then writes `~/.config/opencode/opencode.json` for enabled Home Manager users. The package's own update mechanism is disabled because Nix owns its version.

Provider credentials remain in SOPS secret files. `credentialFiles` maps environment variable names to those runtime paths. The `opencode` launcher reads them when the process starts; neither the values nor generated authentication files enter the Nix store. A user with the feature enabled must be allowed to read the referenced files. Interactive provider logins remain OpenCode-owned local state.

`features/dev/openchamber` exposes two optional interfaces on hosts with OpenCode enabled. The web/CLI package is locked to the published `@openchamber/web` npm dependency graph and provides the `openchamber` command. The desktop package wraps the official Linux AppImage and provides a desktop launcher. Both packages use the same OpenChamber release version. Their launchers set `OPENCODE_BINARY` to the host's OpenCode launcher, so both interfaces use the same Nix-managed version and runtime credentials.

The workstation and notebook enable both interfaces for the primary Home Manager user. The web interface binds to loopback by default and starts only when invoked with `openchamber`; the desktop interface starts from its launcher. No listener or firewall rule is created by these features.
