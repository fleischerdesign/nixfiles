{ lib, pkgs, ... }:
{
  options.my.features.dev.codex = {
    enable = lib.mkEnableOption "Codex CLI and editor integration for Home Manager users";
    package = lib.mkPackageOption pkgs "codex" { };
  };
  config.home-manager.sharedModules = [ ./home.nix ];
}
