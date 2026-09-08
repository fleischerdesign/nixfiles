# roles/base.nix
# Base system configurations applicable to all hosts (servers and personal computers).
{ config, lib, ... }: {
  my.features = {
    system = {
      common.enable = lib.mkDefault true;
      bootloader = {
        enable = lib.mkDefault true;
        provider = lib.mkDefault "systemd-boot";
      };
      kernel.enable = lib.mkDefault true;
      fish-shell.enable = lib.mkDefault true;
      networking.topology.enable = lib.mkDefault true;
      security.enable = lib.mkDefault true;
    };
  };

  my.features.system.networking.ssh.enable = lib.mkDefault true;

  # dsh (DeepSeek Harness) runs as a persistent system-wide daemon (dedicated
  # `dsh` system user, DSH_HOME=/var/lib/dsh, MTAA layout) on every host. It is
  # always a systemd SYSTEM service; this merely turns the daemon on.
  my.features.dev.dsh.web.enable = lib.mkDefault true;

  # LLM credentials + default model for the dsh agent, shared by every host
  # (the daemon is system-wide). DeepSeek is the primary route; OpenRouter is
  # the fallback / multi-provider route. These secrets are encrypted for all
  # hosts (see .sops.yaml) and consumed via the dsh credentials service.
  sops.secrets."pi/deepseek" = lib.mkDefault { };
  sops.secrets."pi/openrouter" = lib.mkDefault { };

  my.features.dev.dsh = {
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
      provider = "deepseek-official";
      model = "deepseek-v4-flash-vision-exp";
    };

    deepseek = {
      thinking = lib.mkDefault "enabled";
      reasoningEffort = lib.mkDefault "low";
    };
  };

  nod = {
    enable = lib.mkDefault true;
    targetHost = lib.mkDefault (
      config.my.features.system.networking.topology.hosts.${config.networking.hostName}.tailscaleIp
        or config.networking.hostName
    );
    role = lib.mkDefault config.my.role;
    tags = lib.mkDefault [ ];
    ssh = {
      user = lib.mkDefault "root";
      identityFile = lib.mkDefault "~/.ssh/deploy-key";
    };
    healthChecks = {
      enable = lib.mkDefault true;
      systemd = {
        checkRunning = lib.mkDefault true;
        checkFailedUnits = lib.mkDefault true;
      };
    };
  };
}
