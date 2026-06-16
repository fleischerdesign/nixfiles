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
      environment = {
        MNEMOSYNE_EMBEDDING_MODEL = "intfloat/multilingual-e5-small";
      };
      settings = {
        model = {
          default = cfg.model;
          provider = "deepseek";
        };
        memory = {
          provider = "mnemosyne";
          memory_enabled = false;
          user_profile_enabled = false;
        };
      };
      environmentFiles = [ config.sops.secrets.hermes_agent_env.path ];
    };

    # Secret environment file containing API keys like OPENROUTER_API_KEY
    sops.secrets.hermes_agent_env = {
      owner = "hermes";
      restartUnits = [ "hermes-agent.service" ];
    };

    # Bootstrap Mnemosyne memory provider inside the container
    systemd.services.hermes-agent-mnemosyne-bootstrap = {
      description = "Bootstrap Mnemosyne memory provider inside Hermes container";
      wantedBy = [ "hermes-agent.service" ];
      after = [ "hermes-agent.service" ];
      requires = [ "hermes-agent.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = false;
        User = "root";
      };
      path = with pkgs; [ docker ];
      script = ''
        for i in $(seq 1 30); do
          if docker inspect hermes-agent --format='{{.State.Running}}' 2>/dev/null | grep -q true; then
            break
          fi
          sleep 2
        done
        docker exec hermes-agent \
          /home/hermes/.venv/bin/pip install -q "mnemosyne-hermes[embeddings]"
        docker exec hermes-agent \
          /home/hermes/.venv/bin/mnemosyne-hermes --hermes-home /data/.hermes install --force
      '';
    };

    # Dynamically add all configured host users to the hermes group
    users.users = lib.genAttrs cfg.hostUsers (_user: {
      extraGroups = [ "hermes" ];
    });
  };
}
