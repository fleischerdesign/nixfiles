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

    hardening = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Enable zero-overhead kernel memory protection and network-stack anti-spoofing hardening.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    security.sudo = lib.mkIf cfg.sudo.enable {
      enable = true;
      extraRules = lib.optionals cfg.sudo.passwordlessRebuild [
        {
          users = [ config.my.user.primary ];
          commands = [
            {
              command = "/run/current-system/sw/bin/nixos-rebuild";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nixos-rebuild *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nh";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nh *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nix-env";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nix-env *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.nix}/bin/nix-env";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.nix}/bin/nix-env *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nix-collect-garbage";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/run/current-system/sw/bin/nix-collect-garbage *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.nix}/bin/nix-collect-garbage";
              options = [ "NOPASSWD" ];
            }
            {
              command = "${pkgs.nix}/bin/nix-collect-garbage *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/switch";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/switch *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/boot";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/boot *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/test";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/test *";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/dry-activate";
              options = [ "NOPASSWD" ];
            }
            {
              command = "/nix/store/*-nixos-system-*/bin/dry-activate *";
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

    # Zero-Overhead Kernel & Network-Stack Hardening Baseline (docs/security.md 4.1)
    boot = lib.mkIf cfg.hardening.enable {
      kernelParams = [
        "slab_nomerge" # Zero-overhead heap protection
        "page_alloc.shuffle=1" # Randomize page allocation against heap-spraying
      ];

      kernel.sysctl = {
        # Address space & reconnaissance protection
        "kernel.kptr_restrict" = 2;
        "kernel.dmesg_restrict" = 1;
        "kernel.unprivileged_bpf_disabled" = 1;

        # Network stack hardening (Anti-spoofing & SYN-flood protection)
        "net.ipv4.tcp_syncookies" = 1;
        "net.ipv4.conf.all.rp_filter" = 1;
        "net.ipv4.conf.default.rp_filter" = 1;
        "net.ipv4.conf.all.accept_redirects" = 0;
        "net.ipv4.conf.default.accept_redirects" = 0;
        "net.ipv4.conf.all.send_redirects" = 0;
        "net.ipv6.conf.all.accept_redirects" = 0;
      };
    };
  };
}
