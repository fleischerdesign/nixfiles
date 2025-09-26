{ lib, pkgs, config, ... }:

let
  cfg = config.my.homeManager.modules.nixvim;
in
{
  config = lib.mkIf cfg.enable {
    programs.nixvim = {
      enable = true;
      opts.number = true;
      opts.relativenumber = true;
    };
  };
}
