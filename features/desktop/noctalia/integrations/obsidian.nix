# Obsidian. The community template renders a CSS snippet into each vault and enables it
# in that vault's appearance.json; its hook does the enabling with python3. The vault is
# not Home Manager-owned, so the tool the hook needs is declared next to the selection.
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
  config = lib.mkIf (cfg.enable && config.programs.obsidian.enable) {
    my.features.desktop.noctalia.settings.theme.templates.community_ids = [ "obsidian" ];

    home.packages = [ pkgs.python3 ];
  };
}
