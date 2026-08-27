# features/dev/pi/plugins/pi-mcp-adapter/module.nix
# Model Context Protocol (MCP) adapter plugin for Pi.
{
  lib,
  ...
}:
{
  options.my.features.dev.pi.plugins.mcp-adapter = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable Model Context Protocol (MCP) adapter plugin.";
    };

    mcpFooterStatus = lib.mkOption {
      type = lib.types.enum [
        "full"
        "compact"
        "off"
      ];
      default = "off";
      description = "Footer status indicator mode for pi-mcp-adapter.";
    };

    disableProxyTool = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Hide the mcp proxy tool once direct tools are resolved.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.attrsOf lib.types.anything;
      default = { };
      description = "Additional raw options merged into mcp.json settings.";
    };
  };
}
