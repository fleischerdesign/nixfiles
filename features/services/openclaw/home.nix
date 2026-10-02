{
  config,
  lib,
  osConfig,
  ...
}:
let
  nodes = lib.filterAttrs (
    _: node: node.user == config.home.username
  ) osConfig.my.features.services.openclaw.sessionNodes;
in
{
  systemd.user.services = lib.mapAttrs (_: node: builtins.removeAttrs node [ "user" ]) nodes;
}
