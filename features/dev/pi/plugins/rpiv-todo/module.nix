# features/dev/pi/plugins/rpiv-todo/module.nix
# Persistent task-tree management plugin for Pi.
{
  lib,
  ...
}:
{
  options.my.features.dev.pi.plugins.rpiv-todo = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable persistent task-tree management plugin.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options for rpiv-todo.";
    };
  };
}
