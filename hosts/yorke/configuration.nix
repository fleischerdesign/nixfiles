{
  config,
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

  my.features.dev.pi = {
    enable = true;
    provider = "deepseek";
    defaultModel = "DeepSeek-V4-Flash-Vision-Exp";
    providers = {
      deepseek.apiKey = config.sops.placeholder."pi/deepseek";
      openrouter.apiKey = config.sops.placeholder."pi/openrouter";
    };
  };

  sops.secrets."pi/deepseek" = { };
  sops.secrets."pi/openrouter" = { };

  # Capability authorization — local E2E test on yorke. Enforcement is
  # default-deny; the operator grant (`group:wheel`) covers the config repo +
  # dev tree + tenant store, so in-scope reads flow and out-of-scope reads
  # (e.g. /etc/passwd) are denied.
  my.features.dev.dsh.authorization = {
    enable = true;
    pathTools = [
      "read"
      "write"
      "edit"
      "glob"
      "bash"
    ];
    grants = [
      {
        principal = "group:wheel";
        resources = [
          "path:/etc/nixos/**"
          "path:/home/philipp/dev/**"
          "path:/var/lib/dsh/tenants/**"
        ];
        actions = [
          "read"
          "write"
          "mutate"
          "exec"
        ];
      }
    ];
  };

  system.stateVersion = "24.05";
}
