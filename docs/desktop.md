# Desktop

> **Scope:** the graphical sessions of `hom-wrk-01` and `mob-nb-01`
> **Owner of the session:** [`features/desktop/`](../features/desktop/)
> **Naming and planes:** see [architecture.md](architecture.md), [naming.md](naming.md).

## 1. One graphical session per host

A host runs **at most one** graphical session. A compositor or desktop environment registers that
session; a shell running inside it does not. Two sessions would compete for the same seat. The
invariant lives in the desktop contract, [`contracts/desktop/nixos.nix`](../contracts/desktop/nixos.nix): a desktop feature
registers itself under `my.desktop.environments` when it is enabled, and the contract refuses a host
where more than one has. The contract holds no list of the environments it knows, so adding a
desktop is one feature and one host switch, never an edit to a central list.

`hom-wrk-01` runs **Niri** with **Noctalia Shell**. greetd starts Niri directly as the host's
primary user, without an authentication screen: physical access after boot means access to that
account. The Niri and Noctalia feature switches live in the host's `configuration.nix`.
`mob-nb-01` runs **GNOME** with **GDM**.

## 2. What each layer owns

| Layer | Owns | Where |
|---|---|---|
| Nixpkgs GNOME module | the session's services: dconf, Polkit, xdg portals, gvfs, keyring, power profiles, NetworkManager, GNOME Shell | pinned `nixpkgs-unstable`, not repeated here |
| `contracts/desktop/nixos.nix` | the one-session invariant, fed by the features' self-registration | contract |
| `features/desktop/gnome/nixos.nix` | GDM, the session pinned by name, the set of core apps this site does not install | system |
| `features/desktop/gnome/home.nix` | GNOME defaults and the typed options for personal settings | per user |
| `features/desktop/niri/nixos.nix` | Niri session, greetd direct start as the primary user, Niri services and portals | system |
| `features/desktop/niri/home.nix` | Compositor layout, keyboard, navigation and window rules | per user |
| `features/desktop/noctalia/nixos.nix` | the Noctalia feature switch; no second session | system |
| `features/desktop/noctalia/home.nix` | Noctalia's Home Manager module and Niri-specific startup/IPC adapter | per user |
| `user/<name>/home.nix` | the actual personal choices: wallpaper, favourites, battery indicator | per user |
| host configuration | session and shell choice, monitor and hardware facts | host |

The system module sets only what the GNOME module does not. This is deliberate: a module that
re-states `services.gvfs.enable` or `programs.dconf.enable` would look authoritative while saying
nothing, and would drift the day upstream changes.

## 3. Niri and Noctalia

Niri is independent of a particular shell: the host declares output positions, Niri owns its
Wayland session and navigation, and Noctalia owns its package, launcher/lock/media/screenshot keybindings,
wallpaper, notifications and Polkit prompt. Its Home Manager module installs the pinned nixpkgs
package; Niri starts it exactly once, rather than enabling a second systemd user service. The
desktop shell does not open a network port. The workstation already enables NetworkManager,
Bluetooth, UPower, and a power-profile service through its existing modules; Noctalia does not
enable another copy of these services.

The Niri adapter floats Noctalia's settings window, honors its notification-driven window
activation, and maps launcher, control center, settings, window switcher, screenshots, lock, audio and
brightness shortcuts. The shell captures through the compositor's image-copy protocol, so no external
screenshot tool is installed; a capture is copied by default, and the annotation editor is bound too.
`Mod+Comma` stays Niri's consume-window action; Noctalia settings use
`Mod+Shift+Comma`. The overview uses Noctalia's blurred wallpaper backdrop, with its own
background layer placed inside Niri's backdrop. On Niri 26.04, Noctalia surfaces use non-xray
blur so the content behind them is sampled instead of the wallpaper; other applications are not
globally blurred. These compositor rules live in the shell adapter and leave Niri usable without
Noctalia.

Noctalia reads declarative `~/.config/noctalia/config.toml`, then overlays mutable settings in
`~/.local/state/noctalia/settings.toml`. GUI changes therefore take precedence over the declared
defaults. The personal wallpaper is set in `user/philipp/home.nix`, not the shared feature.
The same user file selects a wallpaper-derived palette with pure-black dark surfaces, places the
Control Center near its bar trigger, supplies the personal avatar from `media/avatar-philipp.jpg`
and gives Noctalia an explicit geocoded address instead of IP-based location. The photograph is
part of this repository and its Nix store closure; geocoding sends the declared address to the
location service.

The shell feature owns every seam between itself and an application. `home.nix` holds the shell and
its Niri adapter; `features/desktop/noctalia/integrations/<app>.nix` holds one application each - the
template it selects together with the configuration that makes that application consume the palette -
and is active only where the application is enabled. An application feature therefore never names the
shell, which `checks/niri-noctalia.nix` enforces with a grep over `features/`. Built-in templates
whose seam is the template itself (Btop, KColorScheme, Niri, whose seam is the include in the
adapter) are listed in `home.nix`.

Where an application does not own its own configuration, the selection is declared here rather than
left to a runtime hook: a Home Manager file is a symlink into the store and not writable, so
Noctalia's hooks for Ghostty, Niri and Neovim cannot edit it. Ghostty's theme, the Niri include,
qt6ct's colour scheme and Neovim's loader are therefore declarations; GTK, Btop and the KColorScheme
consumer write their own files. Neovim's community template is vendored here as
`templates/neovim-base16.lua` and rendered as a user template without a hook: that template's hook
registers its loader by appending to `~/.config/nvim/init.lua`, which Home Manager owns and the hook
can therefore never change, so selecting it as a community template would only produce a failing
hook on every palette change.

The VS Code theme extension keeps a mutable extensions directory, because VS Code only accepts a
theme file inside its extension directory; the two files that identify the extension stay Home
Manager-owned, and the theme file is seeded once and owned by the shell after that. A Home Manager
generation that managed the extensions directory immutably leaves a store symlink at that path, so
an activation entry removes exactly that link before linking the new layout. Community template files
are downloaded after the first render, so a oneshot waits for the selected catalog to be cached and
then triggers one apply; it fails loudly when that does not happen within its bound.

The shell's plugin selection is declared the same way. Each plugin integration adds its own entry to
`settings.plugins.enabled` together with the packages that plugin needs as a prerequisite -
`bitwarden-cli` for Bitwarden, `scrcpy` for Phone Operate, `system-config-printer` for Printers - and
`settings.plugins.auto_update = "none"` keeps the plugin code at the revision it was first fetched, so
updates are an explicit act. The phone plugin needs more than its own package: it calls `scrcpy`,
`adb`, `sshfs` and `gdbus` as external commands, and on NixOS none of those arrives with another
package's PATH, so each is declared and the check verifies the built session profile actually exposes
them. A prerequisite that is a system service rather than a package is
declared where it belongs: `programs.kdeconnect` in the host's configuration owns KDE Connect's
daemon and opens its ports, because that is a machine decision with a firewall consequence, not a
user package. Per-plugin options live under `settings.plugin_settings.<author>/<plugin>`, keyed
exactly as the plugin's manifest declares them.

One plugin needs a secret: Home Assistant's access token. It cannot be written into a store file, so
`features/desktop/noctalia/config.nix` generates the configuration, has sops-nix render it with the
user's own age identity, and links `~/.config/noctalia/config.toml` at the rendered file through a
Home Manager out-of-store symlink. `my.features.desktop.noctalia.settings` remains the single
declaration, `programs.noctalia.settings` is deliberately unused, and `checks/niri-noctalia.nix`
validates the rendered generation with a placeholder token instead of the secret. The token is
Klipper's Moonraker token by explicit decision: one credential now has two consumers, which
[security.md](security.md) §3.1 records rather than hides. A running shell does not notice that its
configuration file was replaced, because the file is a symlink whose target moved, so a user service
restarts when the generated configuration changes, tells the shell to reload, and fails loudly if it
never answers.

The bar is a personal choice and lives in `user/philipp/home.nix`: workspaces at the start, media and
the anchored clock in the centre, then state - system indicators first, then the plugin states - and
finally attention and action (the privacy indicator, notifications, clipboard, control center, session). The launcher and
wallpaper widgets are dropped: the launcher is reached with `Mod+Space`, and the wallpaper is declared
in this repository, so a button for it would only invite drift. The control center carries the useful
toggles plus the microphone mute; power profiles are not worth a slot on a desktop. Home Assistant's
entities are deliberately not declared - which entity a toggle means is a personal decision, so it is
chosen in the shell, not in this repository.

Direct login passes no password to PAM, so the login keyring is locked at boot and the first client
that wants a secret would raise its own unlock dialog. The shell therefore starts locked: the one
password the lock screen already takes unlocks the session and the keyring together, because that
unlock runs `pam_gnome_keyring`, and Noctalia's encrypted clipboard storage opens with it.

## 4. GNOME user settings

The Home Manager half is imported on every host, but its `enable` option defaults to
`osConfig.my.features.desktop.gnome.enable`. On a host that does not run GNOME the options exist and
their settings are inert, so a user file can declare personal GNOME configuration unconditionally.

`features/desktop/gnome/home.nix` defines the options; it does not choose values. Favourites,
wallpaper and the battery indicator are written only when the user declared them, which is what
keeps one account from inheriting another's choices.

Two settings are structural rather than personal and therefore default in the shared module: the
colour scheme (`prefer-dark`) and the keyboard layout. GNOME on Wayland reads its layout from
`org.gnome.desktop.input-sources`, **not** from `services.xserver.xkb`, so
`my.features.desktop.gnome.inputSources` is the declaration that actually reaches the session.

## 5. GNOME Shell extensions

Extensions are Home Manager's single list, `programs.gnome-shell.extensions`: it installs each
package and enables the UUID derived from it, so the installed set and the enabled set cannot
drift. The shared module ships **none** and writes `disable-user-extensions = true` while the list
is empty, making "classic GNOME" a stated default rather than a side effect; the moment the list is
non-empty that setting yields to Home Manager's own.

On the notebook the primary user enables five, all verified against the pinned GNOME Shell release:
Tiling Shell, GSConnect, Vitals, Blur my Shell and Dash to Dock. Per-extension settings are dconf keys under
that extension's schema (`org.gnome.shell.extensions.<name>`), declared in the same `home.nix`;
GSConnect keeps its state at runtime because pairing is not configuration.

## 6. Verification

[`checks/gnome-desktop.nix`](../checks/gnome-desktop.nix) separates two kinds of statement: system
invariants are read from the notebook (session, GDM, exclusions, the exclusivity rule), while
module behaviour is read from fixtures whose values the check states itself - so changing a
favourite, a wallpaper or an extension never edits the check.
The extension list is only read to verify, per package metadata, that every enabled extension
declares support for the pinned shell release. The desktop is a graphical session, so nothing short
of logging in proves it on hardware: login, lock/unlock, keyring unlock, suspend/resume, external
monitors, screen sharing, Bluetooth and brightness are exercised by the operator, not by evaluation.

[`checks/niri-noctalia.nix`](../checks/niri-noctalia.nix) states properties, not a copy of the
configuration. A claim is either a relation between two declarations - an integration that selects a
template must also wire the application that reads it, and a bar widget that names a plugin must name
an enabled one - or a requirement the design cannot work without. Personal values (which widget sits
in which lane, which address is configured) are deliberately not asserted: changing them is not a
defect, and asserting them would only mean editing the check every time a preference changes. A
violated claim is named in the error; that is how a bar widget that addressed a misspelled plugin id
was found. The check validates the generated Niri KDL and Noctalia TOML with their pinned
executables, and treats every Noctalia warning as a failure except the one the sandbox must produce
per declared plugin setting, because the validator exits successfully even for settings it ignored.
Evaluation cannot prove that the compositor, lock screen, outputs, keyring and suspend work on
physical hardware; they require a local login.
