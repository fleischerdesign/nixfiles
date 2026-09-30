# Firefox. Noctalia's built-in native host consumes the community palette and pushes
# it to Pywalfox. The template hook owns the writable native messaging manifest;
# Home Manager installs the extension through policies without managing profiles.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf (cfg.enable && config.programs.firefox.enable) {
    my.features.desktop.noctalia.settings.theme.templates.community_ids = [ "pywalfox" ];

    programs.firefox.policies.ExtensionSettings."pywalfox@frewacom.org" = {
      installation_mode = "force_installed";
      install_url = "https://addons.mozilla.org/firefox/downloads/latest/pywalfox/latest.xpi";
    };
  };
}
