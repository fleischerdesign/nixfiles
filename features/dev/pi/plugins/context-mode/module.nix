# features/dev/pi/plugins/context-mode/module.nix
# Context trimming & summarization plugin for Pi.
{
  lib,
  config,
  ...
}:
{
  options.my.features.dev.pi.plugins.context-mode = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable context trimming & summarization plugin.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options for context-mode.";
    };
  };

  config = lib.mkIf (config.my.features.dev.pi.plugins.context-mode.extraConfig != { }) {
    assertions = [
      {
        assertion = false;
        message = "my.features.dev.pi.plugins.context-mode.extraConfig has no supported serialization path yet.";
      }
    ];
  };
}
