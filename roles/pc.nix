# roles/pc.nix
# This is the base role for any "Personal Computer", whether desktop or notebook.
{
  config,
  lib,
  ...
}:
{
  imports = [
    ./base.nix
  ];

  hardware.enableRedistributableFirmware = lib.mkDefault true;

  my.user.extraGroups = lib.mkDefault [
    "networkmanager"
    "wheel"
    "adbusers"
    "input"
    "uinput"
  ];

  # It enables a baseline set of features common to all graphical systems.
  my.features.system = {
    audio.enable = lib.mkDefault true;
    wayland.enable = lib.mkDefault true;
    printing.enable = lib.mkDefault true;
  };

  my.features.desktop = {
    webapps.enable = lib.mkDefault true;
  };

  my.features.dev = {
    containers.enable = lib.mkDefault true;
    codium.enable = lib.mkDefault true;
    nixvim.enable = lib.mkDefault true;
    obsidian.enable = lib.mkDefault true;

    dsh = {
      credentials = {
        "DEEPSEEK_API_KEY".key = lib.mkDefault config.sops.placeholder."pi/deepseek";
        "OPENROUTER_API_KEY".key = lib.mkDefault config.sops.placeholder."pi/openrouter";
      };

      piAi.providers = {
        openrouter.apiKeyEnv = lib.mkDefault "OPENROUTER_API_KEY";
        openrouter-contributor = {
          displayName = lib.mkDefault "OpenRouter (Contributor)";
          apiKeyEnv = lib.mkDefault "OPENROUTER_API_KEY";
          api = lib.mkDefault "openai-completions";
          baseURL = lib.mkDefault "https://openrouter.ai/api/v1";
          models = lib.mkDefault [
            {
              id = "meta/muse-spark-1.3-contributor";
              name = "Muse Spark 1.3 (Contributor)";
              contextWindow = 1048576;
              maxTokens = 943718;
              input = [
                "text"
                "image"
              ];
            }
          ];
        };
      };

      defaultModel = lib.mkDefault {
        provider = "deepseek";
        model = "deepseek-v4-flash-vision-exp";
      };

      deepseek = {
        thinking = lib.mkDefault "enabled";
        reasoningEffort = lib.mkDefault "high";
      };

      web.enable = lib.mkDefault true;
    };
  };

  my.features.media = {
    gaming.enable = lib.mkDefault true;
    spotify.enable = lib.mkDefault true;
  };

  services.xserver.xkb.layout = lib.mkDefault "de";
}
