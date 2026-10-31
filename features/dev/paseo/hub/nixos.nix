# Paseo Hub: the layer above the daemons. It receives events from GitHub, Linear, Slack and
# Discord, matches them against triggers kept in a repository, and asks a named daemon to run an
# agent. The daemons keep running agents where they always did; Hub only decides when to ask.
#
# Upstream calls Hub early development, so this module stays deliberately thin: one process, an
# embedded database under its own state directory, a port, and nothing that pretends to manage
# triggers - those live in `.paseo/triggers/` beside the code they serve and are deployed with the
# Hub CLI.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.my.features.dev.paseo.hub;
in
{
  options.my.features.dev.paseo.hub = {
    enable = lib.mkEnableOption "the Paseo Hub";

    package = lib.mkOption {
      type = lib.types.package;
      # nixpkgs carries the tagged release; upstream has no flake to follow, and Hub's own
      # changelog marks it as pre-stable, so a reviewed nixpkgs revision is the safer pin.
      default = pkgs.paseo-hub;
      defaultText = lib.literalExpression "pkgs.paseo-hub";
      description = "Paseo Hub package.";
    };

    port = lib.mkOption {
      type = lib.types.port;
      # 3000 is Grafana's port on the ingress host; a default that collides fails only on the one
      # host that runs both, which is the kind of defect nobody finds by reading the module.
      default = 7670;
      description = "HTTP port; upstream reads it from PORT.";
    };

    stateDir = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/paseo-hub";
      description = "Hub state: the embedded database and its runtime files.";
    };

    user = lib.mkOption {
      type = lib.types.str;
      default = "paseo-hub";
      description = "Account the Hub runs as.";
    };

    group = lib.mkOption {
      type = lib.types.str;
      default = "paseo-hub";
      description = "Group of the Hub account and its state directory.";
    };
  };

  config = lib.mkIf cfg.enable {
    users.groups.${cfg.group} = { };
    users.users.${cfg.user} = {
      isSystemUser = true;
      inherit (cfg) group;
      home = cfg.stateDir;
      description = "Paseo Hub";
    };

    systemd.services.paseo-hub = {
      description = "Paseo Hub";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      environment = {
        PORT = toString cfg.port;
        HOME = cfg.stateDir;
        # The embedded database lives under the XDG data directory; StateDirectory owns it.
        XDG_DATA_HOME = cfg.stateDir;
      };
      serviceConfig = {
        Type = "simple";
        ExecStart = "${cfg.package}/bin/paseo-hub";
        inherit (cfg) user group;
        StateDirectory = baseNameOf cfg.stateDir;
        Restart = "always";
        RestartSec = 2;
      };
    };

    # Hub receives the webhooks that start an agent, so it needs a name of its own. It keeps its
    # own operator account, which is why the ingress adds no second authentication in front of it.
    my.contracts.provides.paseo-hub = {
      publications."web" = {
        scope = "public";
        endpoint = "web";
        auth = "none";
        subdomain = "paseo";
        publicExempt = "enforces its own operator login; webhook senders cannot perform a browser SSO redirect";
      };
      presentation.tiles."web" = {
        endpoint = "web";
        description = {
          de = "Agenten aus GitHub, Slack und Discord starten.";
          en = "Start agents from GitHub, Slack and Discord.";
        };
        show = true;
        displayName = "Paseo Hub";
        category = "Observability & Tools";
        icon = "globe";
      };
      telemetry.probes."web-http".endpoint = "web";
      telemetry.probes."web-http".kind = "http";
      endpoints.web = {
        port = cfg.port;
        protocol = "tcp";
      };
      storage.stateDirs = [ cfg.stateDir ];
    };
  };
}
