# Ghostty. The template writes the theme file; the terminal's own configuration must
# select it, and that file is Home Manager-owned, so the selection is declared here.
# `mkDefault` keeps a user override possible.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf (cfg.enable && config.programs.ghostty.enable) {
    programs.noctalia.settings.theme.templates.builtin_ids = [ "ghostty" ];

    programs.ghostty.settings.theme = lib.mkDefault "noctalia";
  };
}
