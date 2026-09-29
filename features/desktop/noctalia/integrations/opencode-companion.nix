# OpenCode Companion. The plugin drives the OpenCode HTTP API, so it is selected exactly
# where this host installs OpenCode; the provider authentication stays in OpenCode's own
# runtime state.
{
  config,
  lib,
  osConfig ? { },
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
in
{
  config = lib.mkIf (cfg.enable && (osConfig.my.features.dev.opencode.enable or false)) {
    my.features.desktop.noctalia.settings.plugins.enabled = [ "weinguyen/opencode-companion" ];
  };
}
