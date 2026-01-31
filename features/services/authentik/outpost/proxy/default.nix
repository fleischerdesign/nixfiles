{ config, lib, pkgs, ... }:
let
  cfg = config.my.features.services.authentik.outpost.proxy;
in
{
  options.my.features.services.authentik.outpost.proxy.enable = lib.mkEnableOption "Authentik Proxy Outpost";

  config = lib.mkIf cfg.enable {
    # 1. Secrets Setup
    sops.defaultSopsFile = ../../../../../secrets/secrets.yaml;
    sops.secrets."authentik_token" = {
      owner = "authentik-outpost";
      # Restart service when secret changes
      restartUnits = [ "authentik-outpost-proxy.service" ];
    };

    # 2. Template to format the token as Environment Variable
    # Creates a file with: AUTHENTIK_TOKEN=value
    sops.templates."authentik-outpost.env".content = ''
      AUTHENTIK_TOKEN=${config.sops.placeholder."authentik_token"}
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
        
        # Configure connection to Authentik Core
        Environment = [
            "AUTHENTIK_HOST=https://auth.igy.ancoris.ovh"
            "AUTHENTIK_HOST_BROWSER=https://auth.igy.ancoris.ovh"
            "AUTHENTIK_INSECURE_SKIP_VERIFY=false"
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
        
        