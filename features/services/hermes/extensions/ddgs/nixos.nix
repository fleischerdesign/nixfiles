{ config, lib, ... }:
let
  hcfg = config.my.features.services.hermes;
  ecfg = config.my.features.services.hermes.extensions.ddgs;
in
{
  options.my.features.services.hermes.extensions.ddgs = {
    enable = lib.mkEnableOption "DuckDuckGo search package extension";
  };

  config = lib.mkIf (hcfg.enable && ecfg.enable) {
  };
}
