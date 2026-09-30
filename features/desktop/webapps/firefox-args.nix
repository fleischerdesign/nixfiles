# A deliberately unregistered ID selects Firefox's native find-or-create path.
# Firefox owns the real UUID, registry and desktop integration. Never seed its
# internal JSON or mistake this bootstrap token for the persistent app identity.
{
  url,
  container ? 0,
}:
[
  "-taskbar-tab"
  "nix-webapp-bootstrap"
  "-new-window"
  url
  "-container"
  (toString container)
]
