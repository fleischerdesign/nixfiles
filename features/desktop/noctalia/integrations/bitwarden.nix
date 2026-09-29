# Bitwarden. The plugin reads the vault through the CLI's local API, so the CLI is the
# prerequisite; the vault session is a runtime secret and is not part of this declaration.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf cfg.enable {
    my.features.desktop.noctalia.settings.plugins.enabled = [ "noctalia/bitwarden" ];

    home.packages = [ pkgs.bitwarden-cli ];
  };
}
