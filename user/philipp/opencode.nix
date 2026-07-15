{
  lib,
  pkgs,
  osConfig,
  ...
}:
let
  role = osConfig.my.role;
in
{
  programs.opencode = lib.mkIf (role != "server") {
    enable = true;
    extraPackages = [ pkgs.nodejs ];
    settings = {
      mcp = {
        nixos = {
          type = "local";
          command = [ (lib.getExe pkgs.mcp-nixos) ];
          enabled = true;
        };
        chrome-devtools = {
          type = "local";
          command = [
            "npx"
            "-y"
            "chrome-devtools-mcp@latest"
            "--executablePath"
            (lib.getExe pkgs.google-chrome)
          ];
          enabled = true;
        };
      };
      plugin = [
        "context-mode"
        "opencode-pty"
        "opencode-direnv"
      ];
    };
  };
}
