# CUPS printers. The plugin drives the client tools, so it is selected exactly where this
# host runs the printing feature; `system-config-printer` is what its settings button opens.
{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf (cfg.enable && (osConfig.my.features.system.printing.enable or false)) {
    my.features.desktop.noctalia.settings.plugins.enabled = [ "andrewdems/printers" ];

    home.packages = [ pkgs.system-config-printer ];
  };
}
