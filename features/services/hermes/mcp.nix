{ config, lib, ... }:
let
  cfg = config.my.features.services.hermes;
in
{
  options.services.hermes-agent.mcpServers = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.submodule {
        options = {
          command = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          args = lib.mkOption {
            type = lib.types.listOf lib.types.str;
            default = [ ];
          };
          env = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
          url = lib.mkOption {
            type = lib.types.nullOr lib.types.str;
            default = null;
          };
          headers = lib.mkOption {
            type = lib.types.attrsOf lib.types.str;
            default = { };
          };
          enabled = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };
          timeout = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.unsigned;
            default = null;
          };
          connect_timeout = lib.mkOption {
            type = lib.types.nullOr lib.types.ints.unsigned;
            default = null;
          };
        };
      }
    );
    default = { };
    description = "MCP server definitions bridged into hermes-agent settings.";
  };

  config = lib.mkIf (cfg.enable && config.services.hermes-agent.mcpServers != { }) {
    services.hermes-agent.settings.mcp_servers = lib.mapAttrs (
      _name: srv:
      (lib.optionalAttrs (srv.command != null) {
        inherit (srv) command args;
      })
      // (lib.optionalAttrs (srv.env != { }) {
        inherit (srv) env;
      })
      // (lib.optionalAttrs (srv.url != null) {
        inherit (srv) url;
      })
      // (lib.optionalAttrs (srv.headers != { }) {
        inherit (srv) headers;
      })
      // {
        inherit (srv) enabled;
      }
      // (lib.optionalAttrs (srv.timeout != null) {
        inherit (srv) timeout;
      })
      // (lib.optionalAttrs (srv.connect_timeout != null) {
        inherit (srv) connect_timeout;
      })
    ) config.services.hermes-agent.mcpServers;
  };
}
