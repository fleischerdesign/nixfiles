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

  # Capability-based authorization test grant (operator). Enforcement is on:
  # default-deny except within the granted resources, so an out-of-scope tool
  # call (e.g. read /etc/passwd) is denied. `group:wheel` dominates for the
  # operator's principal via its live IdP group membership (agnostic — no
  # hardcoded username/sub). After the E2E test this can be removed or kept as
  # the operator base grant.
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
