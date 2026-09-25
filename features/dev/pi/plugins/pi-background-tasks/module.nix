# features/dev/pi/plugins/pi-background-tasks/module.nix
# Durable background shell tasks & async process management plugin for Pi.
{
  lib,
  config,
  ...
}:
{
  options.my.features.dev.pi.plugins.pi-background-tasks = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable durable background shell tasks & async process management plugin.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options for pi-background-tasks.";
    };
  };

  config = lib.mkIf (config.my.features.dev.pi.plugins.pi-background-tasks.extraConfig != { }) {
    assertions = [
      {
        assertion = false;
        message = "my.features.dev.pi.plugins.pi-background-tasks.extraConfig has no supported serialization path yet.";
      }
    ];
  };
}
