# features/dev/openclaw/default.nix — OpenClaw CLI Home Manager & System Feature Module
#
# Architecture & Guidelines:
# - User-Scoped Level (home-manager.sharedModules): Exposes my.features.dev.openclaw.enable for HM users.
# - Agnostic & Generic: Zero hardcoded usernames or hostnames. Reusable across NixOS & Home Manager.
# - Secret Management: Transparent Out-of-Store Symlink to sops template for ~/.openclaw/openclaw.json,
#   ensuring gateway credentials and passwords never leak into the Nix store.
# - Defaults to the local loopback tunnel on port 18790 established by openclaw.node,
#   or configurable to any target gateway.
{
  config,
  lib,
  ...
}:
let
  cfg = config.my.features.dev.openclaw;
in
{
  options.my.features.dev.openclaw = {
    enable = lib.mkEnableOption "system-wide OpenClaw CLI secrets template";

    gateway = {
      host = lib.mkOption {
        type = lib.types.str;
        default = "127.0.0.1";
        description = "Target gateway host (loopback tunnel or direct host).";
      };

      port = lib.mkOption {
        type = lib.types.port;
        default = 18790;
        description = "Target gateway port.";
      };

      tls = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "Whether to use TLS (wss://) for connecting to the gateway.";
      };

      passwordSecret = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = "openclaw_gateway_password";
        description = "SOPS secret key containing the gateway auth password.";
      };
    };
  };

  config = lib.mkMerge [
    {
      home-manager.sharedModules = [
        (
          {
            config,
            lib,
            pkgs,
            osConfig ? { },
            ...
          }:
          let
            userCfg = config.my.features.dev.openclaw;
          in
          {
            options.my.features.dev.openclaw = {
              enable = lib.mkEnableOption "OpenClaw CLI integration for this Home Manager user";

              package = lib.mkOption {
                type = lib.types.package;
                default = pkgs.openclaw;
                description = "OpenClaw CLI package.";
              };
            };

            config = lib.mkIf userCfg.enable {
              home.packages = [ userCfg.package ];

              home.file = lib.mkIf (osConfig ? sops && osConfig.sops.templates ? "openclaw-cli.json") {
                ".openclaw/openclaw.json".source =
                  config.lib.file.mkOutOfStoreSymlink
                    osConfig.sops.templates."openclaw-cli.json".path;
              };
            };
          }
        )
      ];
    }

    (lib.mkIf cfg.enable {
      sops.templates = lib.optionalAttrs (cfg.gateway.passwordSecret != null) {
        "openclaw-cli.json" = {
          owner = config.my.user.name;
          content = builtins.toJSON {
            gateway = {
              mode = "remote";
              port = cfg.gateway.port;
              remote = {
                url = "${
                  if cfg.gateway.tls then "wss" else "ws"
                }://${cfg.gateway.host}:${toString cfg.gateway.port}";
                password = config.sops.placeholder.${cfg.gateway.passwordSecret};
              };
            };
          };
        };
      };
    })
  ];
}
