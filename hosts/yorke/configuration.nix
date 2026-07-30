{
  config,
  pkgs,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/notebook.nix
  ];

  networking.hostName = "yorke";

  # Features
  my.features.desktop.niri.enable = true;

  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;

  my.features.media.gaming.sunshine.enable = false;
  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  my.features.dev.opencode = {
    enable = true;
    settings = {
      model = "deepseek/deepseek-v4-pro";
      small_model = "deepseek/deepseek-v4-flash";
      autoupdate = false;
      instructions = [ "~/.config/opencode/instructions/engineering-constitution.md" ];
      provider = {
        deepseek = {
          options = {
            timeout = 600000;
            chunkTimeout = 30000;
            setCacheKey = true;
          };
        };
      };
      mcp = {
        nixos = {
          type = "local";
          command = [ "${pkgs.mcp-nixos}/bin/mcp-nixos" ];
          enabled = true;
        };
        chrome-devtools = {
          type = "local";
          command = [
            "npx"
            "-y"
            "chrome-devtools-mcp@latest"
            "--executablePath"
            "${pkgs.google-chrome}/bin/google-chrome-stable"
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
    providers = {
      deepseek.apiKey = config.sops.placeholder."opencode/deepseek";
      openrouter.apiKey = config.sops.placeholder."opencode/openrouter";
    };
  };

  sops.secrets."opencode/deepseek" = { };
  sops.secrets."opencode/openrouter" = { };

  system.stateVersion = "24.05";
}
