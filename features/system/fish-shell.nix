# features/system/fish-shell.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.fish-shell;
in
{
  options.my.features.system.fish-shell = {
    enable = lib.mkEnableOption "Fish shell as default shell";
  };

  config = lib.mkIf cfg.enable {
    programs.fish.enable = true;
    users.defaultUserShell = pkgs.fish;
  };
}
