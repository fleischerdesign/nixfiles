# OpenChamber

OpenChamber is the browser and desktop client for the OpenCode sessions on `cld-ops-01`. The server
owns the projects and the agent state under one account; a desktop only holds a device-scoped token.

## Server

`my.features.dev.openchamber.server.enable` runs the pinned upstream OpenChamber 2.6.0 package and
its bundled OpenCode 2.2.5 CLI. There is no second OpenCode pin and no fleet process service for it:
the packaged CLI is what the server and the desktop ship.

- Account: `openchamber` (system user, no login). State and projects: `/var/lib/openchamber`, declared
  in the storage contract and therefore in the backup.
- Listener: the host's WireGuard address on port `7337`, never `0.0.0.0`. The firewall admits exactly
  the desktop devices and the hand-paired phone over the `wireguard` interface. There is no
  publication, no public name and no ingress hop: the service is reached directly at
  `http://10.10.100.2:7337` over the mesh.
- Password: `services/openchamber/ui_password` from `secrets/openchamber-server.yaml`, readable by
  root and the `openchamber-bootstrap` group. The upstream module loads it with
  `LoadCredential`; the local mint helper reads the same file. Clients never decrypt it.

The endpoint declares `directAccess.interface = "wireguard"` with the device hosts as
`fromHosts`, so the port is closed on every other interface. WireGuard provides transport
confidentiality; authentication is OpenChamber's own UI password and device tokens.

No telemetry probe is declared: the monitoring contract's local probe targets `127.0.0.1`, while
this listener is bound to the WireGuard address. Adding one would report a healthy server as down;
a mesh-target probe is a separate monitoring-contract change.

## Devices

The authoritative allowlist is `my.features.dev.openchamber.server.devices`. Its attribute names are
device ids and must equal the client host names.

Each device has a dedicated Ed25519 keypair:

- private half in `secrets/openchamber-device-<id>.yaml`, encrypted to that host and the operator;
- public half in the server's `devices` entry;
- an `authorized_keys` line of the form
  `restrict,command="<mint store path>/bin/openchamber-mint <id>" ssh-ed25519 …`.

The device id comes from that literal argument, never from the client. `restrict` disables pty,
forwarding and agent access; no `environment=` is used and `PermitUserEnvironment` stays off.

### Bootstrap path

The client wrapper runs before the app and the patched `entry.mjs` runs again before the
single-instance lock on every start, including `app.relaunch()`. The adapter:

1. probes the stored token with `GET /auth/session`;
2. if missing or `401`, runs the Nix-declared SSH command over `StrictHostKeyChecking=yes` and the
   inventory-pinned `ssh_known_hosts`;
3. the forced command signs in with the server password, takes the session cookie and calls
   `POST /api/client-auth/clients` with `label = openchamber-bootstrap:<id>`, `clientKind = desktop`
   and `dedupeKey = device:<id>`;
4. writes the returned token only into OpenChamber's `settings.json`, atomically, mode `0600`,
   preserving every unmanaged key and host.

The token is a bearer credential in a `0600` file. Upstream passes the configured host and token to
its renderer process for the connection, so a compromised renderer can read it; that is upstream's
trust boundary, unchanged by this repository. The adapter never writes the token to argv, a log, the
Nix store or the registry.

The client-management route is used instead of the login route's `issueClientToken` because the latter
attaches the UI session's expiry. `deviceName` is not accepted by the client-management route; the
managed namespace is the label prefix, which is what the revocation reconciler reads.

`OPENCHAMBER_SERVER_URL` is not used: that branch empties `clientToken`. The desktop selects its host
from `desktopHosts` and `desktopDefaultHostId`, which is the path the adapter writes.

### Revocation

Removing an entry from `server.devices` does two things in the same activation:

- the SSH grant disappears, so the device can no longer mint;
- `openchamber-revoke.service` (also on a 15-minute timer) revokes any token whose label is in the
  `openchamber-bootstrap:` namespace and whose device id is no longer allowed.

A re-added device can mint again; upstream's dedupe replacement then clears the revoked record. A
device that was never in the allowlist cannot mint at all. A manually paired phone is outside the
managed namespace and is not affected by the reconciler.

The phone is not in `devices` and receives no SSH grant. It is listed in
`my.features.dev.openchamber.server.meshClientHosts` so the same listener is reachable from its
mesh identity (`mob-ph-01`); pairing it by hand means opening `http://10.10.100.2:7337` while the
phone is on the mesh and signing in with the UI password. A phone that is not a mesh member cannot
reach the service.

## Desktop

`my.features.dev.openchamber.client.enable` installs the patched desktop package, a token-free
registry, the launcher wrapper and the session environment hook. The desktop package carries one
narrow source patch: a provisioning hook immediately before `app.requestSingleInstanceLock()` in
`packages/electron/entry.mjs`. The patch is version-guarded to 2.6.0 and fails the build when upstream
moves the insertion point.

There is no local OpenCode server on the client: `OPENCHAMBER_SKIP_LOCAL_SERVER=1` is exported.

## Adding a device

1. Generate a keypair and encrypt the private half to the new host and the operator:
   `sops --encrypt --filename-override secrets/openchamber-device-<id>.yaml …` after adding the
   matching `creation_rules` entry.
2. Add the public half to `my.features.dev.openchamber.server.devices.<id>`.
3. Enable `my.features.dev.openchamber.client` on the client host.
4. Deploy; the client provisions itself on first start.

## Verifying

```bash
nix build .#checks.x86_64-linux.openchamber-api
nix build .#checks.x86_64-linux.openchamber-provision
nix build .#checks.x86_64-linux.openchamber-provision-hook
nix build .#checks.x86_64-linux.openchamber-devices
```

On the server, `systemctl cat openchamber` shows the mesh bind and `LoadCredential`; the built
`/etc/ssh/authorized_keys.d/openchamber-bootstrap` shows one restricted line per allowed device. On a
client, the token appears only in `~/.config/openchamber/settings.json`. The client's `serverUrl` is
derived from the server host's WireGuard address and the endpoint port, never from a publication.

### Live canary before the clients start

The checks above prove the rendered configuration and the HTTP routes, but they do not run `sshd`
against the real bootstrap account. Before the two desktop clients are enabled, run this canary once
from `hom-wrk-01` (the token is deliberately discarded):

```bash
ssh -i /run/secrets/services/openchamber/devices/hom-wrk-01/ssh_key \
  -o IdentitiesOnly=yes -o BatchMode=yes -o StrictHostKeyChecking=yes \
  openchamber-bootstrap@10.10.100.2 'touch /tmp/openchamber-forced-command-escaped' >/dev/null
```

Then on `cld-ops-01`:

```bash
test ! -e /tmp/openchamber-forced-command-escaped   # the client's command never runs
ssh -tt -i <the same key> openchamber-bootstrap@10.10.100.2 true   # must fail to allocate a pty
```

An `exit 0` from the first command means the forced mint ran; a `mint:` message on stderr means the
helper reached the configuration boundary. A shell prompt, or the escaped file, means the forced
command is not in effect - stop and do not enable a client.
