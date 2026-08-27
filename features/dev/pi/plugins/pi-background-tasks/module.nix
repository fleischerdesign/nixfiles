# features/dev/pi/plugins/pi-background-tasks/module.nix
# Durable background shell tasks & async process management plugin for Pi.
{
  lib,
  ...
}:
{
  options.my.features.dev.pi.plugins.pi-background-tasks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable durable background shell tasks & async process management plugin.";
    };

    enableFusion = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable multi-model Fusion consensus tools (fusion_investigate, fusion_reason, etc.).";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options for pi-background-tasks.";
    };
  };
}
