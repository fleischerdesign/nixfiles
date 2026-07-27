# features/services/hermes/extensions/ddgs/nixos.nix — DDGS extension
#
# DuckDuckGo search provider for hermes-agent. This is a package-only
# extension — it provides a Python package injected via extraPythonPackages
# but requires no additional service or configuration.
{ config, lib, ... }:
let
  hcfg = config.my.features.services.hermes;
  ecfg = config.my.features.services.hermes.extensions.ddgs;
in
{
  options.my.features.services.hermes.extensions.ddgs = {
    enable = lib.mkEnableOption "DuckDuckGo search package extension";
    pluginName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = "ddgs";
      internal = true;
      description = "Plugin name registered in config.yaml plugins.enabled.";
    };
  };

  config = lib.mkIf (hcfg.enable && ecfg.enable) {
  };
}
