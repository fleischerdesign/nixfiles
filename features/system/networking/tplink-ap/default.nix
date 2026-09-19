# features/system/networking/tplink-ap/default.nix
# Declarative TP-Link RE330 Access Point GitOps Engine (tplinkrouterc6u API / Option A).
# Reconciles Wi-Fi settings, Unified SSID, and maintenance state idempotently from `my.topology`.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.system.networking.tplink-ap;
  topology = config.my.topology;
  apHost = topology.hosts.hom-ap-01 or null;

  # Render desired state configuration as JSON derivation
  desiredStateJson = pkgs.writeText "tplink-ap-desired-state.json" (
    builtins.toJSON {
      host = cfg.host;
      user = cfg.user;
      passwordSecret = cfg.passwordSecret;
      settings = {
        wifi = {
          ssid = cfg.settings.wifi.ssid;
          enable2G = cfg.settings.wifi.enable2G;
          enable5G = cfg.settings.wifi.enable5G;
        };
      };
    }
  );

  # Hermetic Python interpreter with custom tplinkrouterc6u package
  pythonEnv = pkgs.python3.withPackages (_: [
    pkgs.custom.tplinkrouterc6u
  ]);

  # Executable wrapper
  syncScript = pkgs.writeShellScriptBin "tplink-ap-sync" ''
    exec ${pythonEnv}/bin/python3 ${./sync.py} --spec ${desiredStateJson} "$@"
  '';
in
{
  options.my.features.system.networking.tplink-ap = {
    enable = lib.mkEnableOption "Declarative TP-Link RE330 Access Point GitOps Engine";

    host = lib.mkOption {
      type = lib.types.str;
      default =
        let
          migrationAddresses = if apHost == null then [ ] else apHost.migration.addresses;
        in
        if migrationAddresses != [ ] then
          # Still on the old network: reach it where it currently answers.
          lib.head (lib.splitString "/" (lib.head migrationAddresses))
        else if apHost != null && apHost.ipv4 != null then
          apHost.ipv4
        else
          "10.10.10.20";
      description = ''
        Management address of the access point. While the topology declares a `migration`
        address the AP is reached there (it has not moved yet); `ipv4` stays the target address.
      '';
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "admin";
      description = "Management username configured on the access point";
    };

    passwordSecret = lib.mkOption {
      type = lib.types.str;
      default = "services/wifi/ap_password";
      description = "SOPS secret identifier containing the RE330 management password";
    };

    settings = {
      wifi = {
        ssid = lib.mkOption {
          type = lib.types.str;
          default = "VYRX";
          description = "Unified Dual-Band SSID broadcasted across 2.4 GHz and 5 GHz (Option A)";
        };

        enable2G = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable 2.4 GHz radio band";
        };

        enable5G = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = "Enable 5 GHz radio band";
        };
      };
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = syncScript;
      readOnly = true;
      description = "The compiled tplink-ap-sync executable package";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
