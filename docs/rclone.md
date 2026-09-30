# User-scoped remote mounts

`features/system/rclone` owns provider-independent FUSE mounts and one systemd user service per
named remote. Only `roles/pc.nix` enables the host feature; servers have no rclone mount services.
`user/philipp/rclone.nix` selects personal remotes and binds them to `graphical-session.target`.
Nautilus bookmarks are a separate graphical integration in `user/philipp/rclone-bookmarks.nix`,
which appends missing locations without replacing existing bookmarks.

## Paths and lifetime

Mounts live at `~/mounts/<name>`: `gdrive` and the inventory's server hostnames. Mounts neither sync
the full remote locally nor provide a backup. Cache lives at `$XDG_CACHE_HOME/rclone/<name>`.
Drive and SFTP use the `writes` VFS cache, with a soft 2 GiB limit per mount and 24-hour unused-file
retention; open files and pending uploads may exceed that limit. Server mounts are writable wherever
the personal server account has write permission, with no automatic privilege escalation.

Foreground `rclone mount` reports mount readiness with systemd `Type=notify`. It receives SIGTERM
at service stop and handles unmounting itself. Services retry failures after 30 seconds, independently
of one another. Missing configuration or credential files skip startup via `ConditionPathExists`;
after setup, explicitly start the skipped service. Rclone's normal refusal of nonempty mount points
is not bypassed. No lazy unmount, `allow-other`, sync job or cache-deletion hook is configured.
A busy or stale mount requires operator attention rather than forcibly discarding open handles.

Session termination and power loss do not guarantee completed uploads. Keep the write cache intact
and restart the same mount/configuration to resume pending work. Do not move the cache or remote
identity while uploads are outstanding. Suspend/network recovery and actual remote transfers must
be verified on the deployed PCs; Nix evaluation is not proof of online availability.

## Google Drive setup

Google OAuth is interactive and independent on each PC. The refreshable configuration lives at
`~/.config/rclone/gdrive.conf`, outside Git and the Nix store. The parent directory is created with
mode `0700`; use a restrictive umask when creating the file:

```fish
umask 077
rclone config --config ~/.config/rclone/gdrive.conf
```

Create a remote named `gdrive`, type `drive`, with scope `drive` for read/write access. Use your own
Google OAuth desktop client ID and client secret: upstream states that its shared client is being
retired during 2026. Enable the Drive API and follow the upstream
[client-ID instructions](https://rclone.org/drive/#making-your-own-client-id). A Google OAuth app
left in testing mode may have short-lived refresh tokens; follow Google's requirements for the
chosen publishing status. Do not paste credentials or tokens into chat or Nix configuration.

Select the personal drive rather than a Shared Drive unless explicitly desired. Google-native
documents appear as `link.html` links that open in Chrome, not as editable Office exports. Ordinary
uploaded files retain their original types. Shortcuts follow rclone's default backend behaviour;
no separate mount of Shared Drives or Google Photos is implied.

After login:

```fish
chmod 600 ~/.config/rclone/gdrive.conf
systemctl --user start rclone-gdrive.service
```

Open a regular file and upload a disposable test file, then confirm the result in the Drive web
interface. The cache is demand-driven, not a complete offline copy. Some applications may require
`cacheMode = "full"`; enable it only when their observed I/O needs it, with the same bounded cache.

## Server access

SFTP peers derive from `my.topology.hosts` with `hostType = "server"`; addresses are their mesh IPv4
addresses, and ports follow the peers' SSH contracts. Each mounts `/`, using the personal account's
normal permissions. Protected files remain inaccessible; no root access or sudo is configured.

`inventory/ssh.nix` declares server Ed25519 host keys obtained over authenticated administrative
connections. Rclone validates them against `/etc/ssh/ssh_known_hosts`; a missing/mismatched key
fails closed. It explicitly negotiates Ed25519, matching those pinned trust anchors rather than
selecting an unpinned RSA/ECDSA host key. Host-key rotation requires updating the inventory after independently authenticating
the replacement. No unauthenticated key scan or automatic trust-on-first-use is used.

Rclone uses the existing personal key through the session's GCR SSH agent (`%t/gcr/ssh`). The
personal configuration selects `~/.ssh/id_rsa.pub` via `key_file = ~/.ssh/id_rsa` and
`key_use_agent = true`, so rclone uses only that matching agent identity, even if deployment keys
are also loaded. It does not read the private key. The filename is historical: the operator's
current key at this path is Ed25519. Server user authorizations remain unchanged.

Each PC needs the personal key already configured and unlocked in its agent. If necessary:

```fish
ssh-add ~/.ssh/id_rsa
systemctl --user restart rclone-cld-edge-01.service rclone-cld-ops-01.service rclone-hom-srv-01.service
```

Do not copy or generate a new private key automatically. The existing server account permissions
apply to reads and writes; no read-only restriction is imposed by the mount or SSH configuration.
Rclone disables remote shell/hash probing because these mounts do not need remote command execution;
this does not alter what the user's SSH key can do outside rclone. Never use the fleet deploy key
for normal browsing. Only the PC configurations need deployment for these mounts.
SFTP/FUSE does not reproduce every Linux filesystem feature: virtual files, sockets, devices and
some symbolic links are not usable like local files. This is not a chroot or POSIX administration
interface. Do not run databases or containers on these mounts.

## Operations

```fish
systemctl --user status 'rclone-*.service'
journalctl --user -u rclone-gdrive.service
systemctl --user restart rclone-hom-srv-01.service
```

Mount directories are private to the user by default. Existing plocate defaults prune `fuse.rclone`;
current Restic roots do not include these home-directory mounts. Any future recursive home backup
or indexer must explicitly exclude `~/mounts` to avoid fetching the remotes.

Sources: [rclone mount](https://rclone.org/commands/rclone_mount/),
[Drive](https://rclone.org/drive/), [SFTP](https://rclone.org/sftp/).
