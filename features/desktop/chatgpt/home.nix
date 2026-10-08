{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
{
  options.my.features.desktop.chatgpt.enable = lib.mkEnableOption "ChatGPT desktop for this user";
  config =
    lib.mkIf (osConfig.my.features.desktop.chatgpt.enable && config.my.features.desktop.chatgpt.enable)
      {
        home.packages = [ pkgs.custom.chatgpt-linux ];
        xdg.mimeApps.defaultApplications."x-scheme-handler/codex" = "chatgpt.desktop";
      };
}
