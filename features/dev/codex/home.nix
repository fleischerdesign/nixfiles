{
  config,
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  system = osConfig.my.features.dev.codex;
  cfg = config.my.features.dev.codex;
in
{
  options.my.features.dev.codex.enable = lib.mkEnableOption "Codex for this user";
  config = lib.mkIf (system.enable && cfg.enable) {
    home.packages = [ system.package ];
    programs.vscode.profiles.default.extensions = lib.mkIf config.programs.vscode.enable [
      pkgs.vscode-marketplace.openai.chatgpt
    ];
  };
}
