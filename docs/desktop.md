# Desktop

> **Scope:** the graphical sessions of `hom-wrk-01` and `mob-nb-01`; the session is owned by
> [`features/desktop/`](../features/desktop/). Names are in [architecture.md](architecture.md) §5.

## 1. One graphical session per host

A host runs at most one graphical session. A compositor or desktop environment registers that session; a
shell running inside it does not, because two sessions would compete for the same seat. The invariant lives
in the desktop contract: a desktop feature registers itself under `my.desktop.environments` when it is
enabled, and the contract refuses a host where more than one has. The contract holds no list of the
environments it knows, so adding a desktop is one feature and one host switch, never an edit to a central
list.

`hom-wrk-01` and `mob-nb-01` run **Niri** with **Noctalia Shell**: every personal computer takes the same
session from `roles/pc.nix`, and a host states only its output layout. `greetd` asks for credentials through
the Noctalia Greeter and then starts that session, so login and desktop look alike. The greeter is also why
the login keyring is unlocked at session start: a password at login gives `pam_gnome_keyring` the authtok it
needs, which a direct start without credentials could never provide.

## 2. What each layer owns

| Layer | Owns |
|---|---|
| Nixpkgs Niri module | the session services: xdg portals, gvfs, keyring, power profiles, NetworkManager, Bluetooth |
| `contracts/desktop` | the one-session invariant, fed by the self-registration of the features |
| `roles/pc.nix` | the session every personal computer runs and the service prerequisites of its shell |
| `features/desktop/niri`, `features/desktop/noctalia` | the session, the compositor layout and the shell, including the background-effect projection |
| `user/<name>/home.nix` | personal choices: wallpaper, palette, bar layout, favourites |
| host configuration | output layout and hardware facts |

The system module sets only what the pinned Nixpkgs session modules do not. Re-stating `services.gvfs.enable`
would look authoritative while saying nothing, and would drift the day upstream changes.

## 3. Niri and Noctalia

Niri is independent of a particular shell: the compositor owns its Wayland session and navigation, and
Noctalia owns its package, launcher and lock, media, screenshot keybindings, wallpaper, notifications and the
Polkit prompt. Its Home Manager module installs the pinned package, and Niri starts it exactly once rather
than enabling a second user service; the shell opens no network port.

Background effects are declared, not written as compositor rules: `my.desktop.effects` states which surface
or window wants one and what it samples, and the Niri feature projects every entry into exactly one layer or
window rule, so no entry names a compositor. One value, `my.desktop.surfaceOpacity`, decides how opaque every
frosted surface paints its background, so bar, panels, notifications, OSD, dock and terminal cannot drift
apart. The rules leave Niri usable without Noctalia.

Noctalia reads the declarative `~/.config/noctalia/config.toml` and then overlays mutable settings in
`~/.local/state/noctalia/settings.toml`, so interface changes take precedence over the declared defaults.
The personal wallpaper and palette live in `user/philipp/home.nix`.

The shell feature owns every seam between itself and an application:
`features/desktop/noctalia/integrations/<app>.nix` holds one application each and is active only where that
application is enabled, so an application feature never names the shell - `checks/niri-noctalia.nix`
enforces that with a grep over `features/`. Where an application does not own its own configuration (a Home
Manager file is a store symlink and not writable), the selection is declared rather than left to a runtime
hook: the Ghostty theme, the Niri include, the qt6ct colour scheme and the Neovim loader are declarations,
while GTK, Btop and the KColorScheme consumer write their own files. The VS Code theme extension keeps a
mutable extensions directory, because VS Code accepts a theme only inside its extension directory; the two
files that identify the extension stay Home Manager-owned.

One plugin needs a secret, the Home Assistant access token. It cannot live in a store file, so the feature
generates the configuration, sops-nix renders it with the age identity of the user, and the file is linked at
the rendered path through a Home Manager out-of-store symlink. The token is the Klipper Moonraker token by
decision: one credential with two consumers, recorded in [identity.md](identity.md) §2. A running shell does
not notice that its configuration file was replaced, so a user service restarts on change, tells the shell to
reload, and fails loudly if it never answers.

The bar is a personal choice in `user/philipp/home.nix`: workspaces first, then media and the anchored clock,
then state, then attention and action. The launcher and wallpaper widgets are dropped, because the launcher
is reached with a key binding and the wallpaper is declared here. Home Assistant entities are deliberately
not declared: which entity a toggle means is a personal decision.

The greeter shares the appearance of the desktop instead of copying it: scheme `Synced` lets the shell write
palette, wallpaper, font and monitor layout into the mutable `sync.toml` next to the declarative
`greeter.toml`, and polkit authorises the constrained apply helper for the primary user, so what that user
own session looks like needs no admin prompt. `greeter.toml` always wins where it sets a value.

## 4. GNOME

GNOME remains an available desktop feature with its own GDM session and per-user options, but no host enables
it - both personal computers take the session from `roles/pc.nix`. Its Home Manager half is imported
everywhere and inert where the feature is disabled, so a future host could run it without touching the Niri
side.

## 5. Browser and webapps

`features/desktop/webapps` owns the desktop launchers; personal app declarations stay in
`user/philipp/home.nix`. Each app inherits `defaultBrowser` unless it selects another engine; the personal
default is Google Chrome. Chrome, Brave and Epiphany are launched in application mode with shell wrappers
that preserve argument boundaries and propagate the exit status. Chrome webapps use the ordinary browser
profile by default; explicit `isolated = true` gives a separate profile under `~/.config/webapps/<name>`,
and unsupported isolation is rejected at evaluation time. No browser profile is replaced, migrated or
deleted.

`checks/webapps.nix` verifies the generated launchers for both graphical host classes, default inheritance,
explicit overrides, unsupported isolation and MIME defaults, plus argument boundaries in a shell fixture; it
does not start a browser. After deployment, launch an app and confirm it opens an app window using the normal
browser session - without deleting existing profiles.

## 6. Remote mounts

`features/system/rclone` owns provider-independent FUSE mounts and one systemd user service per named remote;
only `roles/pc.nix` enables the host feature. Mounts live at `~/mounts/<name>` and neither sync the full
remote locally nor provide a backup. Drive and SFTP use the `writes` VFS cache with a soft 2 GiB limit per
mount and 24-hour retention for unused files; open files and pending uploads may exceed it. Foreground
`rclone mount` reports readiness with `Type=notify` and unmounts itself on SIGTERM; missing credentials skip
startup through `ConditionPathExists`, and the service is started explicitly after setup. A busy or stale
mount needs operator attention rather than forcibly discarding open handles, and session termination or power
loss does not guarantee completed uploads: keep the cache and restart the same mount to resume.

**Google Drive** is an interactive OAuth setup per PC, outside Git and the store, at
`~/.config/rclone/gdrive.conf` - created with a restrictive umask and `chmod 600` afterwards. Use an own
OAuth desktop client (the shared upstream client is being retired), and never paste credentials into a chat
or into Nix. **Server mounts** derive from `my.topology.hosts` with `hostType = "server"`, using their mesh
addresses. `inventory/ssh.nix` pins the Ed25519 host keys and rclone validates them against
`/etc/ssh/ssh_known_hosts`, failing closed on a mismatch and negotiating Ed25519 explicitly. The personal key
is used through the GCR SSH agent of the session; the private key is never read, and the fleet deploy key is
never used for browsing.

```fish
systemctl --user status 'rclone-*.service'
journalctl --user -u rclone-gdrive.service
systemctl --user restart rclone-hom-srv-01.service
```

Any future recursive home backup or indexer must exclude `~/mounts` - the mounts are not a backup and are not
a POSIX administration interface. Nautilus bookmarks are a separate graphical integration that appends
missing locations without replacing existing ones.

## 7. Coding agents

The personal-computer role enables the ChatGPT desktop, Codex and OpenCodex, each behind its own Home Manager
switch; servers do not install these applications. `packages/custom/chatgpt-linux` packages the official
OpenAI Linux archive and patches its Linux dependencies; the `codex://` handler belongs to ChatGPT, while
ordinary HTTP and HTTPS defaults stay with the graphical profile. The Codex feature installs the pinned
nixpkgs CLI and the official editor extension where the editor is enabled.

Codex and OpenCodex share their homes with interactive clients (`~/.codex`, `~/.opencodex`); neither directory
is managed as an immutable file. Home Manager owns `opencodex-proxy.service`, which binds `127.0.0.1:10100`,
reads its declared credential files and requires readiness within 45 seconds; missing secrets and failed
readiness fail the unit.

`features/dev/opencode` installs OpenCode v2 from its flake package, writes the global configuration, and puts
a launcher on `PATH` that reads the declared credential files into the environment at start, so no provider
key reaches the Nix store or a unit file and a user with the feature enabled never has to read them by hand.
The default model is the role's declaration and has to exist in the gateway the fleet subscribes to
(`opencode-go`, `https://opencode.ai/zen/go/v1`; `opencode models` lists the catalogue) - an id the gateway
does not offer is a broken default, not a preference.

`features/dev/openchamber` builds on that launcher: the web and desktop interfaces are launchers of the same
OpenCode binary, so an interface and the host share one version and one credential set. `server.enable` adds
a headless instance as a user service on the host's overlay address, which is the port the endpoint contract
opens for the mesh; where the role is a server the feature also sets the operator's `linger`, because nobody
logs in there to start it. The instance reads two secrets from the store at start - `openchamber/ui_password`, without which it
refuses to bind a reachable address, and `openchamber/jwt_secret`, which signs the tokens issued to paired
devices, where a key minted fresh at every start would drop every pairing on every restart. Both are owned by
the operator and exported into the process rather than the unit environment, so no status query prints them.
`server.apiOnly` (default true) serves the API alone, which is what a native client needs, and
`server.publish.enable` puts the interface on a public name the ingress terminates alone: there the ingress is
the authentication boundary, and the central forward-auth outpost answers on the authentik host alone. The
declared audience is `infra-admins`, and a paired application's non-browser WebSocket upgrade is handed
through to the instance, which checks the device token itself. Provider selection and logins beyond the
declared credentials remain runtime state that the user must verify.

## 8. Verification

[`checks/niri-noctalia.nix`](../checks/niri-noctalia.nix) states properties, not a copy of the configuration,
and runs for every host whose contract registration says Niri - the list is derived, so switching a host
session covers it without editing the check. A claim is either a relation between two declarations (an
integration that selects a template must also wire the application that reads it; a bar widget that names a
plugin must name an enabled one) or a requirement the design cannot work without. Personal values are
deliberately not asserted, because asserting them would mean editing the check on every preference change.
The check validates the generated Niri KDL and Noctalia TOML of each host with their pinned executables and
treats every Noctalia warning as a failure except the one the sandbox must produce.

A graphical session is proven only on hardware: login, lock and unlock, keyring unlock, suspend and resume,
external monitors, screen sharing, Bluetooth and brightness are exercised by the operator.
