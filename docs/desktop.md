# Desktop

> **Scope:** the graphical sessions of `hom-wrk-01` and `mob-nb-01`
> **Owner of the session:** [`features/desktop/`](../features/desktop/)
> **Naming and planes:** see [architecture.md](architecture.md), [naming.md](naming.md).

## 1. One desktop per host

A host runs **at most one** desktop environment. Each one owns both a session and a display
manager, and two of them would compete for the same seat. The invariant lives in the desktop
contract, [`contracts/desktop/nixos.nix`](../contracts/desktop/nixos.nix): a desktop feature
registers itself under `my.desktop.environments` when it is enabled, and the contract refuses a host
where more than one has. The contract holds no list of the environments it knows, so adding a
desktop is one feature and one host switch, never an edit to a central list.

`hom-wrk-01` and `mob-nb-01` run **GNOME** with **GDM**. The feature is
`my.features.desktop.gnome.enable`; it is a host fact, set in the host's `configuration.nix`.

## 2. What each layer owns

| Layer | Owns | Where |
|---|---|---|
| Nixpkgs GNOME module | the session's services: dconf, Polkit, xdg portals, gvfs, keyring, power profiles, NetworkManager, GNOME Shell | pinned `nixpkgs-unstable`, not repeated here |
| `contracts/desktop/nixos.nix` | the one-session invariant, fed by the features' self-registration | contract |
| `features/desktop/gnome/nixos.nix` | GDM, the session pinned by name, the set of core apps this site does not install | system |
| `features/desktop/gnome/home.nix` | GNOME defaults and the typed options for personal settings | per user |
| `user/<name>/home.nix` | the actual personal choices: wallpaper, favourites, battery indicator | per user |
| host configuration | that this host runs GNOME at all; monitor and hardware quirks | host |

The system module sets only what the GNOME module does not. This is deliberate: a module that
re-states `services.gvfs.enable` or `programs.dconf.enable` would look authoritative while saying
nothing, and would drift the day upstream changes.

## 3. User settings

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

## 4. GNOME Shell extensions

Extensions are Home Manager's single list, `programs.gnome-shell.extensions`: it installs each
package and enables the UUID derived from it, so the installed set and the enabled set cannot
drift. This site ships **none** by default — the shared module writes
`disable-user-extensions = true` while that list is empty, making "classic GNOME" a stated default
rather than a side effect. Adding an extension is one entry in the user's `home.nix`; the "off"
setting then yields to Home Manager's own.

## 5. Verification

[`checks/gnome-desktop.nix`](../checks/gnome-desktop.nix) asserts the session, GDM, the exclusions,
the user settings, the desktop exclusivity rule and the extension mechanism, each with a negative
control. The desktop is a graphical session, so nothing short of logging in proves it on hardware:
login, lock/unlock, keyring unlock, suspend/resume, external monitors, screen sharing, Bluetooth and
brightness are exercised by the operator, not by evaluation.

The Niri/Axis feature is retained in the tree, disabled, as the rollback path for this migration.
