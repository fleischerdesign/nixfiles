{
  config,
  lib,
  pkgs,
  ...
}:
{
  config = lib.mkIf config.my.nixos.boot.enable {
    boot.loader = {
      # GRUB für EFI-Systeme
      grub = {
        enable = true;
        device = "nodev"; # Universell für alle EFI-Systeme
        efiSupport = true;
        useOSProber = true; # Findet andere OS automatisch

        # Optional: Schöneres Theme
        theme = pkgs.sleek-grub-theme;
      };

      efi = {
        canTouchEfiVariables = true;
      };

      # Falls du systemd-boot deaktivieren willst
      systemd-boot.enable = lib.mkForce false;
    };

    boot.kernelParams = [ "quiet" ];
  };
}
