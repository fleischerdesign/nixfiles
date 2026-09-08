{
  config,
  ...
}:
{
  imports = [
    ./hardware-configuration.nix
    ./hardware-specific.nix
    ../../roles/desktop.nix
  ];

  networking.hostName = "jello";

  # Features
  my.features.system.networking.tailscale.enable = true;
  my.features.system.networking.tailscale.acceptRoutes = true;

  my.features.dev.containers.enable = true;
  my.features.dev.android.enable = true;
  my.features.desktop.niri.enable = true;

  my.features.services.attic.client = {
    enable = true;
    autoPush = true;
  };

  my.features.dev.pi = {
    enable = true;
    provider = "deepseek";
    defaultModel = "DeepSeek-V4-Flash-Vision-Exp";
    providers = {
      deepseek.apiKey = config.sops.placeholder."pi/deepseek";
      openrouter.apiKey = config.sops.placeholder."pi/openrouter";
    };
  };

  # dsh (DeepSeek Harness): local vector embeddings for the memory recall
  # cascade. Provider "api" uses an OpenAI-compatible embeddings endpoint
  # dsh runs as a persistent system-wide daemon (systemd SYSTEM service,
  # dedicated dsh user, DSH_HOME=/var/lib/dsh) on every host.
  my.features.dev.dsh.web.enable = true;

  # (OpenRouter, via the existing dsh credential key) and is agnostic/scalable;
  # BM25 remains as the offline supplement + fallback.
  my.features.dev.dsh.memory.embedding = {
    enable = true;
    provider = "api";
    apiModel = "openai/text-embedding-3-small";
    apiBase = "https://openrouter.ai/api/v1";
    apiKeyEnv = "OPENROUTER_API_KEY";
    dim = 1536;
    topK = 8;
    minSimilarity = 0.5;
    similarityMargin = 0.2;
    weight = 0.7;
    entropyMinStems = 1;
  };

  sops.secrets."pi/deepseek" = { };
  sops.secrets."pi/openrouter" = { };

  system.stateVersion = "24.05";
}
