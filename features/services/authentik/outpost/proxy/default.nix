{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.my.features.services.authentik.outpost.proxy;
in
{
  options.my.features.services.authentik.outpost.proxy = {
    enable = lib.mkEnableOption "Authentik Proxy Outpost";
    tokenSecretName = lib.mkOption {
      type = lib.types.str;
      default = "authentik_outpost_proxy_token";
      description = "The name of the secret in sops containing the Authentik proxy token.";
    };
    coreAddress = lib.mkOption {
      type = lib.types.str;
      default = "http://${config.my.features.system.networking.topology.hosts.mackaye.tailscaleIp}:9055";
      description = "Internal address of the Authentik Core instance.";
    };
    browserUrl = lib.mkOption {
      type = lib.types.str;
      default = "https://auth.ancoris.ovh";
      description = "Public browser facing URL of the Authentik Core instance.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Secrets Setup
    sops.secrets."${cfg.tokenSecretName}" = {
      owner = "authentik-outpost";
      # Restart service when secret changes
      restartUnits = [ "authentik-outpost-proxy.service" ];
    };

    # 2. Template to format the token as Environment Variable
    # Creates a file with: AUTHENTIK_TOKEN=value
    sops.templates."authentik-outpost.env".content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."${cfg.tokenSecretName}"}
    '';

    # Create system user and group for the service
    users.users.authentik-outpost = {
      isSystemUser = true;
      group = "authentik-outpost";
    };
    users.groups.authentik-outpost = { };

    # 3. Systemd Service Definition
    systemd.services.authentik-outpost-proxy = {
      description = "Authentik Proxy Outpost";
      wantedBy = [ "multi-user.target" ];
      after = [ "network.target" ];

      serviceConfig = {
        # Use lib.getExe to resolve the binary name automatically
        ExecStart = lib.getExe pkgs.authentik-outposts.proxy;

        # Load the token from the sops template
        EnvironmentFile = config.sops.templates."authentik-outpost.env".path;

        # Configure connection to Authentik Core via Tailscale
        Environment = [
          "AUTHENTIK_HOST=${cfg.coreAddress}"
          "AUTHENTIK_HOST_BROWSER=${cfg.browserUrl}"
          "AUTHENTIK_INSECURE_SKIP_VERIFY=true"
          # Listen on localhost:9000
          "AUTHENTIK_HTTP_ADDRESS=127.0.0.1:9000"
          "AUTHENTIK_METRICS_ADDRESS=127.0.0.1:9300"
        ];

        Restart = "always";

        # Security: Run as dedicated user

        User = "authentik-outpost";

        Group = "authentik-outpost";

        StateDirectory = "authentik-outpost-proxy";
      };
    };
  };
}
