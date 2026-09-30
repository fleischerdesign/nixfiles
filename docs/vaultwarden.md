# Vaultwarden

## Placement and access

`features/services/vaultwarden/nixos.nix` declares the service; `cld-edge-01` enables it.
The public `web` publication derives `vault.vyrx.de` from the topology and its `vault` subdomain.
Caddy terminates HTTPS and proxies to a loopback listener. Native OIDC, not forward-auth, protects
sign-in, so Bitwarden clients and notification WebSockets use their own protocol unchanged.

The publication's `accessAuthenticated` policy admits active, authenticated humans, including users
without role-group membership, and rejects service accounts. Authentik's compiler produces an explicit
expression-policy binding; an empty audience never silently opens an application. The portal tile
has no group restriction because the application's audience is all authenticated humans.

Normal registration and password-only login are disabled. Authorized SSO users may initialize a new
vault. Each person owns their master password, MFA, vault contents and organization memberships;
SSO authenticates the person but does not decrypt their vault. Global administration is disabled:
no `ADMIN_TOKEN` is configured, and no Authentik group is claimed to grant Vaultwarden admin rights.
The fleet's administrative group remains `infra-admins`.

## OIDC and secrets

The identity contract supplies one client ID, strict callback URI, stable hashed-user subject and
scope selection to both consumers. The authority follows the Authentik core's public publication
and the compiler's application identifier, including the issuer's trailing slash. Access tokens
last 15 minutes; the provider allows `offline_access` and refresh tokens. PKCE is enabled.

`services/apps/vaultwarden_oidc_secret` in `secrets/secrets.yaml` is a single secret value. Authentik
consumes it through its generated secret environment, and SOPS renders `SSO_CLIENT_SECRET` into
Vaultwarden's root-readable runtime environment file. No production credential enters the store.

Authentik's standard email mapping reports an unverified email. Vaultwarden instead selects an
application-specific email mapping that supplies the address without claiming verification.
Unknown verification status is accepted, but automatic association with an initialized non-SSO
vault by email is disabled. Upstream still permits association with uninitialized invitation stubs;
this is not proof of mailbox ownership. Vaultwarden identifies an SSO account by issuer and subject; changing either
requires an explicit account-association recovery procedure, not a silent configuration change.

SMTP uses the [shared outbound transport](smtp.md) for invitation, verification, security and recovery
emails; SMTP authentication is rendered into the runtime environment file by SOPS.
Mobile push through Bitwarden's relay is not enabled. These capabilities are not implied by SSO.
An immutable empty `CONFIG_FILE` prevents admin-generated JSON from overriding the declared
environment. Caddy overwrites `X-Forwarded-For`; Vaultwarden trusts it only from its loopback proxy.

## Desktop clients

The graphical user profile installs the Bitwarden desktop app; the Firefox extension is installed
through browser policies. Select the self-hosted server using the public `web` publication's URL
before signing in to the desktop app or extension. Browser, desktop and CLI sessions are independent;
SSO authentication does not replace the master password needed to unlock the vault.

Noctalia's `noctalia/bitwarden` plugin is reached from the launcher with `/bw`, not through a bar
widget. Its integration installs `bitwarden-cli` and derives `server_url` from the fleet's unique
Vaultwarden `web` publication. Before an API-key login, the plugin runs `bw config server` with that
URL. Obtain the personal API key in the web vault under Settings → Security → Keys; enter it in the
plugin's login panel, then unlock with the master password. Do not put API keys or vault sessions
into Nix configuration. Existing CLI sessions are not automatically logged out or migrated.

The plugin uses `bw serve` on loopback. While unlocked, local processes that can reach its port can
read vault data, so lock the vault when it is not needed. Declarative plugin settings are defaults;
Noctalia's mutable user settings may override them.

## Persistence, backup and recovery

PostgreSQL is local, using a contract-provisioned database and matching peer-authenticated role.
The data directory follows the upstream service's `StateDirectory`, including its state-version
semantics. Keys, attachments and Sends are irreplaceable data; icon and temporary caches are not.
The upstream NixOS service owns its sandboxing, restrictive permissions and restart policy.

The backup contract starts `vaultwarden-snapshot.service` before Restic. The unit stops Vaultwarden,
copies its data without caches, dumps PostgreSQL in custom format, verifies the dump's catalog and
restarts Vaultwarden before any offsite transfer. `/var/backup/vaultwarden/current` contains the
completed `database.dump` and `data/` tree. Staging and the live data tree are excluded from Restic;
the generic PostgreSQL backup remains independent. A failed prepare aborts the backup and attempts
to restart the service, with a nonzero exit status on dump or restart failure.

Recovery requires **both artifacts from the same Restic snapshot**. Stop Vaultwarden, restore the
database into its provisioned PostgreSQL database and the data tree into the declared data directory,
restore service ownership and restrictive permissions, then start the service. Do not import into
a running vault or mix a database dump with attachments from a different snapshot. SOPS material
and an independent Authentik recovery credential must be available outside the vault being recovered.

## Verification

`checks/vaultwarden.nix` evaluates placement, contracts, secret references, unit hardening and the
generated Caddy configuration. `checks/vaultwarden.py` reads the shipped OIDC blueprint and tests
its human-audience policy against anonymous, inactive and service-account negative controls.
It starts the packaged Vaultwarden against an isolated PostgreSQL database, checks health, the
client-facing URL and disabled administration, then restores a database/file fixture from the
snapshot script's output. Dump and restart failures must be visible and attempt service recovery.
Only the snapshot test's systemd/user-switch boundary is mocked; database dumping/restoring and
the Vaultwarden process are real.

These checks do not claim a deployed OIDC login or mobile sync. Runtime acceptance additionally
requires discovery/JWKS validation, sign-in and token refresh with an Authentik user without groups,
rejection of a service account, Bitwarden extension sync and notification WebSocket verification.

Sources: [Vaultwarden SSO documentation](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-SSO-support-using-OpenId-Connect),
[admin panel](https://github.com/dani-garcia/vaultwarden/wiki/Enabling-admin-page), and the Vaultwarden
and Authentik sources pinned by this flake.
