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

## OpenCode Go accounts

`my.features.dev.openchamber.server.goAccounts` seeds the fleet's three OpenCode Go API keys into
OpenCode's own credential store and enables OpenChamber's native account switch. The same SOPS keys
the Gateway already uses for its auth profiles (`ai/opencode_api_key`, `_2`, `_3`) are the only
source; OpenClaw's profiles stay untouched.

- Integration `opencode-go`, model provider `opencode-go`. The provider id is what OpenCode reports
  on a Go model (`opencode-go/<model>`), so `accountSwitchProviders = ["opencode-go"]` reads exactly
  the credential list this module seeds. The shared `opencode` integration is the Console sign-in and
  is not used here.
- The seed unit (`openchamber-go-accounts.service`) runs after the server and reads the keys through
  systemd `LoadCredential`; no key enters the Nix store, the unit environment, argv or a log. A
  changed SOPS value restarts the unit, because each declared secret lists it under `restartUnits`.
- Idempotent by construction: a managed account id is
  `cred_nixfiles_go_<slot>_<hash12>` of a salted SHA-256 of that slot's key. The desired id already
  present means no write at all. A rotation creates the replacement, moves the selection only when
  the replaced row was the selected account, then removes the stale row. A dropped slot removes only
  its own row. With `goAccountCleanup = true`, an empty `goAccounts` list keeps the unit running so
  the same logic removes every managed row and retires the module's `accountSwitchProviders` entry;
  other providers in that list stay. Every other credential, including a manually connected
  ChatGPT/Console login, is never read, activated or removed.
- Writes go through the running server's API (`POST /api/credential`, `POST /api/credential/<id>/activate`,
  `DELETE /api/credential/<id>`, `PUT /api/config/settings`). OpenChamber owns its settings file and
  OpenCode owns the credential store; the seed never writes either directly. The settings key is a
  profile field in `preferences.json`, written through the server's own lock and merge, so UI
  settings and concurrent changes are preserved. Active/selected state is read from OpenCode's
  credential table as metadata (`id`, `active`) only, and only when a rotation needs it.
- The first credential of an integration becomes active even when the create request asks for
  `activate: false`; that is OpenCode's own rule and is why repeated runs never call `activate`.
- Selected-account state is global to the integration, not per session: OpenChamber's switch calls
  OpenCode's `credential.activate`, so every session uses the newly selected account from its next
  request. The exhaustion map lives in the OpenChamber server process and is volatile; a restart
  forgets which accounts ran out, and the next limit starts the rotation again. Nothing here adds a
  second failover, cooldown or proxy.
- A switch is decided on OpenCode's retry hook, after a request failed. Text or tool output already
  streamed before the failure is not replayed by the switch, and a partially streamed turn has no
  continuation guarantee beyond what OpenCode itself retries.

The native switch reacts to `provider.go-limit`, which OpenChamber 2.6.0 omits from two independent
boundaries: the server classifier in `packages/web/server/lib/limit-failover/policy.js` and the
generated plugin source in `runtime.js` (`PLUGIN_SOURCE`). `patch-go-limit.mjs` adds the one type to
both. It is pinned to OpenChamber `v2.6.0` (upstream commit `5731991`) with the bundled OpenCode
2.2.5 and fails the build instead of guessing:

- both boundaries already list `provider.go-limit`: exit 78 and a message naming the patch files to
  remove - upstream fixed it, so the compatibility patch must not survive;
- only one boundary lists it: exit 65 with a review instruction (never a second insertion);
- the pinned version or the exact `LIMIT_ERROR_TYPES` shape moved: exit 65 with a review
  instruction (never a blind replacement).

When the failure appears, re-read the two files at the new revision; if both handle
`provider.go-limit`, delete `packages/overlays/fix/openchamber/patch-go-limit.mjs` and its
`installPhase` line in `packages/overlays/fix/openchamber/default.nix`. The fixture
`nix build .#checks.x86_64-linux.openchamber-go-limit-patch` proves all four outcomes on a tiny
tree; the host build proves the positive application on the real package.

Verification on the server (metadata only, never a key):

```bash
systemctl status openchamber-go-accounts --no-pager
journalctl -u openchamber-go-accounts -n 20 --no-pager   # slot names, counts, ids
```

The provider catalog is reachable only through the UI session; the running accounts can be listed
without values through OpenChamber's Providers page. A key that appears as a connection is accepted
by the auth catalog, which does not prove that the account has an active paid Go plan or quota -
that is visible only in the provider's own usage view.

## Verifying

```bash
nix build .#checks.x86_64-linux.openchamber-provision-hook
nix build .#checks.x86_64-linux.openchamber-devices
```

The HTTP acceptance tests start the real server and pull its 2.4 GB runtime closure, so they are
opt-in and not part of `nix flake check`:

```bash
nix build .#integrationChecks.x86_64-linux.openchamber-api
nix build .#integrationChecks.x86_64-linux.openchamber-provision
```

Run them when the mint, revoke or adapter code changes; the unconditional gate keeps the rendered
configuration and the patch fixture.

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
