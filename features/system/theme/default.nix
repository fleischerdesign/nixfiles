# features/system/theme/default.nix
# Declarative theme assets, branding, and diagnostic status page deployment (DESIGN.md).
# Exposes theme assets to Authentik, Caddy, and local web services.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.theme;

  # Build a combined derivation of all theme assets
  themeAssets = pkgs.runCommand "vyrx-theme-assets" { } ''
    mkdir -p "$out" "$out/errors"
    cp ${./assets/authentik.css} "$out/authentik.css"
    cp ${./assets/logo.svg} "$out/logo.svg"
    cp ${./assets/error-502.html} "$out/errors/502.html"
  '';
in
{
  options.my.features.system.theme = {
    enable = lib.mkEnableOption "VYRX Design System & Theme Engine";
  };

  config = lib.mkIf cfg.enable {
    # 1. Provide theme assets in /etc/vyrx/theme for Caddy and local servers
    environment.etc."vyrx/theme".source = themeAssets;

    # 2. Wire Authentik custom CSS via systemd-tmpfiles when Authentik is enabled on this node
    systemd.tmpfiles.rules = lib.optionals config.my.features.services.authentik.server.enable [
      "d /var/lib/authentik/media 0755 root root -"
      "L+ /var/lib/authentik/media/theme.css - - - - ${themeAssets}/authentik.css"
      "L+ /var/lib/authentik/media/logo.svg - - - - ${themeAssets}/logo.svg"
    ];
  };
}
