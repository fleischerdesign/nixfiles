# features/system/security/default.nix
# Declarative security policy module: targeted passwordless rebuilds, polkit rules, and hardening.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.security;
in
{
  options.my.features.system.security = {
    enable = lib.mkEnableOption "System security policies, sudo rules, and polkit permissions";

    sudo = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable custom sudo rules.";
      };

      passwordlessRebuild = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Allow primary user to execute nixos-rebuild, nh, and nix-collect-garbage without password prompt.";
      };
    };

    polkit = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable polkit rules for passwordless desktop/systemd actions for wheel users.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
      extraRules = lib.optionals cfg.sudo.passwordlessRebuild [
        {
          users = [ config.my.user.name ];
          commands = [
            {
              command = "/run/current-system/sw/bin/nixos-rebuild";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nh";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nix-collect-garbage";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.nix}/bin/nix-collect-garbage";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/boot";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/test";
              options = [ "NOPASSWD" ];
            }
          ];
        }
      ];
    };

    security.polkit = lib.mkIf cfg.polkit.enable {
      enable = true;
      extraConfig = ''
        /* Allow members of wheel group to manage systemd units without password prompt */
        polkit.addRule(function(action, subject) {
          if (action.id == "org.freedesktop.systemd1.manage-units" &&
              subject.isInGroup("wheel")) {
            return polkit.Result.YES;
          }
        });
      '';
    };
  };
}
