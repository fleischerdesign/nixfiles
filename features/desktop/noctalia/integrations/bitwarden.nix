# Bitwarden. The plugin reads the vault through the CLI's local API, so the CLI is the
# prerequisite; the vault session is a runtime secret and is not part of this declaration.
{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
  fleetConfigs = osConfig._module.specialArgs.fleetConfigs;
  systems = fleetConfigs.systems osConfig;
  vaultwardenHost = fleetConfigs.uniqueHost {
    inherit systems;
    matches = host: (host.my.contracts.provides.vaultwarden.publications.web or null) != null;
    role = "Vaultwarden web publication";
  };
  publication = (fleetConfigs.providesOf systems.${vaultwardenHost}).vaultwarden.publications.web;
in
{
  config = lib.mkIf cfg.enable {
    my.features.desktop.noctalia.settings.plugins.enabled = [ "noctalia/bitwarden" ];
    my.features.desktop.noctalia.settings.plugin_settings."noctalia/bitwarden".server_url =
      publication.publicUrl;

    home.packages = [ pkgs.bitwarden-cli ];
  };
}
