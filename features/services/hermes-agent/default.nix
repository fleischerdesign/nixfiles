# features/services/hermes-agent/default.nix
{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:

let
  cfg = config.my.features.services.hermes-agent;
in
{
  options.my.features.services.hermes-agent = {
    enable = lib.mkEnableOption "Hermes Agent";
    model = lib.mkOption {
      type = lib.types.str;
      default = "deepseek-v4-pro";
      description = "Default model for Hermes Agent.";
    };
    hostUsers = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Interactive host users who should have access to the hermes group.";
    };
  };

  imports = [
    inputs.hermes-agent.nixosModules.default
  ];

  config = lib.mkIf cfg.enable {
    services.hermes-agent = {
      enable = true;
      addToSystemPackages = true;
      extraDependencyGroups = [ "messaging" ];
      settings = {
        model = {
          default = cfg.model;
          provider = "deepseek";
        };
      };
      environmentFiles = [ config.sops.secrets.hermes_agent_env.path ];
    };

    # Secret environment file containing API keys like OPENROUTER_API_KEY
    sops.secrets.hermes_agent_env = {
      owner = "hermes";
      restartUnits = [ "hermes-agent.service" ];
    };

    # Dynamically add all configured host users to the hermes group
    users.users = lib.genAttrs cfg.hostUsers (_user: {
      extraGroups = [ "hermes" ];
    });
  };
}
