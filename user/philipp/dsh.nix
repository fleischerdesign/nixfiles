# user/philipp/dsh.nix — dsh (DeepSeek Harness) user configuration for philipp
#
# The dsh harness (and its web surface) runs EQUALLY on every host. The public
# reachability for family login is NOT a per-host dsh setting — it is the Caddy /
# Authentik ingress on `mackaye` (e.g. dsh.mky.ancoris.ovh), wired separately via
# `my.endpoints.dsh` (auto-generates the Caddy vhost + Authentik forward-auth).
_: {
  my.features.dev.dsh.enable = true;
  my.features.dev.dsh.web.enable = true;
  # Caddy reverse-proxies to 127.0.0.1:port, so dsh-web binds loopback everywhere.
  my.features.dev.dsh.web.host = "127.0.0.1";
  my.features.dev.dsh.web.port = 3080;
}
