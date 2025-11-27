# features/system/printing.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.system.printing;
in
{
  options.my.features.system.printing = {
    enable = lib.mkEnableOption "CUPS printing services";
  };

  config = lib.mkIf cfg.enable {
    services.printing.enable = true;
    services.printing.drivers = [ pkgs.hplipWithPlugin ];
  };
}
