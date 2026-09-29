# Home Assistant. The plugin talks to the instance over the internal name; the access token
# is a secret and is injected by ../config.nix, never declared here.
{
  config,
  lib,
  osConfig ? { },
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf cfg.enable {
    my.features.desktop.noctalia.settings = {
      plugins.enabled = [ "pozzoo/hassio" ];
      plugin_settings."pozzoo/hassio".ha_url = "https://hass.${osConfig.my.topology.domain}";
    };
  };
}
