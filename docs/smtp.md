# Outbound application mail

`inventory/smtp.nix` assigns the site's shared transport: `mail-eu.smtp2go.com`, port `2525`,
STARTTLS and `noreply@<topology domain>`. The provider-independent options live in
`features/system/smtp/nixos.nix`; each enabled consumer enables the shared credential declarations.
Other hosts do not materialize these credentials.

`infra/smtp/username` and `infra/smtp/password` in `secrets/secrets.yaml` are the single credential
source. Mealie, Authentik (server and worker) and Vaultwarden consume SOPS-rendered runtime environment
files, not store-owned plaintext. Their templates trigger restarts on configuration changes; secret
rotation follows the SOPS service restart mechanism. Application-specific sender names remain in
the consumer modules. Mealie can override its sender address through `smtpFromEmail`.

Adapters translate the transport's `starttls` / `implicit` modes into Mealie's `TLS` / `SSL`,
Authentik's mutually exclusive `USE_TLS` / `USE_SSL`, and Vaultwarden's `starttls` / `force_tls`.
No adapter disables certificate verification. The SMTP2GO DNS requirements are declared separately
in `inventory/dns.nix`; SMTP does not modify MX records or activate Stalwart.

Deploy `cld-edge-01` for Authentik and Vaultwarden, and `hom-srv-01` for Mealie. Verify a test email
from each application to a mailbox you control, checking the received headers for SPF, DKIM and
DMARC results. SMTP acceptance alone does not prove inbox delivery. Authentik's recovery stage uses
the global transport; its sender must also belong to the verified domain.

The previous Mealie and Brevo secret values remain encrypted in SOPS; they are not deleted as part
of configuring this transport. Disabled Stalwart's declarations remain unchanged.
