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

`hom-wrk-01` and `mob-nb-01` run **Niri** with **Noctalia Shell**: every personal computer takes the
same session from `roles/pc.nix`, and a host states only its output layout. greetd asks for the
credentials through the **Noctalia Greeter** and then starts that session, so login and desktop look
alike. The greeter is the reason the login keyring is unlocked when the session begins: a password at
login gives `pam_gnome_keyring` the authtok it needs, which a direct start without credentials could
never provide. The Niri and Noctalia feature switches default in the role; a host may override them.

## 2. What each layer owns

| Layer | Owns | Where |
|---|---|---|
| Nixpkgs Niri module | the session's services: xdg portals, gvfs, keyring, power profiles, NetworkManager, Bluetooth | pinned `nixpkgs-unstable`, not repeated here |
| `contracts/desktop/nixos.nix` | the one-session invariant, fed by the features' self-registration | contract |
| `roles/pc.nix` | the session every personal computer runs, plus the service prerequisites of its shell | role |
| `features/desktop/niri/nixos.nix` | Niri session, Niri services and portals | system |
| `features/desktop/niri/home.nix` | Compositor layout, keyboard, navigation, window rules and the background-effect projection | per user |
| `features/desktop/noctalia/nixos.nix` | the Noctalia feature switch; no second session | system |
| `features/desktop/noctalia/home.nix` | Noctalia's Home Manager module and Niri-specific startup/IPC adapter | per user |
| `user/<name>/home.nix` | the actual personal choices: wallpaper, favourites, bar layout | per user |
| host configuration | output layout and hardware facts | host |

The system module sets only what the pinned Nixpkgs session modules do not. This is deliberate: a
module that re-states `services.gvfs.enable` or `programs.dconf.enable` would look authoritative
while saying nothing, and would drift the day upstream changes.

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
background layer placed inside Niri's backdrop. Background effects are declared, not written as
compositor rules: `my.desktop.effects` states which surface or window wants one and what it samples,
and the Niri feature projects every entry into exactly one layer or window rule, so no entry names a
compositor. The shell registers its own surfaces and its settings window, a user registers personal
windows, and every entry samples `behind` - what is really under the surface, which is upstream's
recommendation for a realistic blur. One value, `my.desktop.surfaceOpacity`, decides how opaque every
frosted surface paints its background; each owner maps it to its own knob, so bar, panels,
notifications, OSD, dock and the terminal cannot drift apart, and a consumer whose model is discrete
does its own translation. A window's
transparency is its own: Ghostty paints its background translucent and the compositor only blurs what
shows through, and only the background is transparent - no window content is dimmed. GTK applications
get the same treatment from the shell's frost stylesheet, which a second `gtk.css` import pulls in
alongside the palette; because no layout has to name them, the registration blurs behind every window
and an application that stays opaque simply shows nothing. A window may also frost its pop-ups, where
the compositor has to make the pop-up translucent itself, so a menu loses some opacity. Non-xray blur is
experimental upstream and disappears during window open and close
animations; the wallpaper-only mode exists for a surface that must not flicker, and nothing here uses
it. `my.features.desktop.niri.blur` tunes the shared blur and writes nothing unless set, so Niri's own
defaults stand. These compositor rules leave Niri usable without Noctalia.

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

Firefox uses the `pywalfox` community template and the Pywalfox extension, installed through
Firefox policies without declaring or replacing browser profiles. The template's `firefox-theme`
post-action uses Noctalia's built-in native messaging host; no Python Pywalfox package is needed.
Noctalia owns the writable `~/.mozilla/native-messaging-hosts/pywalfox.json` manifest and refreshes
it when applying the palette. Home Manager must not make that file a store symlink. Existing foreign
native hosts are left untouched by Noctalia. Only Theme API colours are configured here, not custom
`userChrome.css` or `userContent.css`.

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

The login is a password login, and that is what the keyring needs. `pam_gnome_keyring` unlocks the
`login` keyring from the authtok the authenticating stack obtained; `greetd` includes the `login`
stack, so the greeter's password reaches it. A direct start, as the site ran before, passed no
password and left the keyring locked until the first client raised its own dialog. Noctalia's
encrypted clipboard storage opens with the keyring, so it works from the first login on.

The greeter shares the desktop's appearance instead of copying it: `appearance.scheme = "Synced"`
lets the shell write its palette, wallpaper, font and monitor layout into the mutable `sync.toml`
next to the declarative `greeter.toml`, and `security.polkit` authorises the constrained apply helper
for the primary user, so no admin prompt is needed for what that user's own session looks like.
`greeter.toml` keeps the session, keyboard layout and cursor and always wins where it sets a value.

## 4. GNOME

GNOME remains an available desktop feature with its own GDM session and per-user options, but no host
enables it: both personal computers take the session from `roles/pc.nix`. Its Home Manager half is
imported everywhere and inert wherever `my.features.desktop.gnome.enable` is false, so a future host
could run it without touching the Niri side.

## 5. Verification

[`checks/niri-noctalia.nix`](../checks/niri-noctalia.nix) states properties, not a copy of the
configuration, and runs for **every** host whose contract registration says Niri - the list is
derived, so switching a host's session covers it without editing the check. A claim is either a
relation between two declarations - an integration that selects a template must also wire the
application that reads it, and a bar widget that names a plugin must name an enabled one - or a
requirement the design cannot work without. Personal values (which widget sits in which lane, which
address is configured) are deliberately not asserted: changing them is not a defect, and asserting
them would only mean editing the check every time a preference changes. A violated claim is named
with its host; that is how a bar widget that addressed a misspelled plugin id was found. The check
validates each host's generated Niri KDL and Noctalia TOML with their pinned executables, and treats
every Noctalia warning as a failure except the one the sandbox must produce per declared plugin
setting, because the validator exits successfully even for settings it ignored.
The desktop is a graphical session, so nothing short of logging in proves it on hardware: login,
lock/unlock, keyring unlock, suspend/resume, external monitors, screen sharing, Bluetooth and
brightness are exercised by the operator, not by evaluation.
