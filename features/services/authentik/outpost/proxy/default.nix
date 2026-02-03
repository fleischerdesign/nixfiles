{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.authentik.outpost.proxy;
in
{
  options.my.features.services.authentik.outpost.proxy.enable = lib.mkEnableOption "Authentik Proxy Outpost";

  config = lib.mkIf cfg.enable {
    # 1. Secrets Setup
    sops.secrets."authentik_outpost_proxy_token" = {
      owner = "authentik-outpost";
      # Restart service when secret changes
      restartUnits = [ "authentik-outpost-proxy.service" ];
    };

    # 2. Template to format the token as Environment Variable
    # Creates a file with: AUTHENTIK_TOKEN=value
    sops.templates."authentik-outpost.env".content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."authentik_outpost_proxy_token"}
    '';

    # Create system user and group for the service
    users.users.authentik-outpost = {
      isSystemUser = true;
      group = "authentik-outpost";
    };
    users.groups.authentik-outpost = {};

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
            "AUTHENTIK_HOST=http://100.120.39.68:9000"
            "AUTHENTIK_HOST_BROWSER=https://auth.ancoris.ovh"
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
        
        