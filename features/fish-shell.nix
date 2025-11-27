# features/fish-shell.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.fish-shell;
in
{
  options.my.features.fish-shell = {
    enable = lib.mkEnableOption "Fish shell as default shell";
  };

  config = lib.mkIf cfg.enable {
    programs.fish.enable = true;
    users.defaultUserShell = pkgs.fish;
  };
}
