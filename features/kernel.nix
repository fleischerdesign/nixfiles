# features/kernel.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.kernel;
in
{
  options.my.features.kernel = {
    enable = lib.mkEnableOption "Kernel configuration (e.g., linuxPackages_testing)";
  };

  config = lib.mkIf cfg.enable {
    boot.kernelPackages = pkgs.linuxPackages_testing;
  };
}
