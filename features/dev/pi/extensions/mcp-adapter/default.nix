# extensions/mcp-adapter/default.nix
# pi-mcp-adapter: MCP protocol bridge. No user-authored config —
# runtime state lives in ~/.pi/agent/mcp.json (managed by /mcp setup).

{ lib, ... }:
{
  options.my.features.dev.pi.extensions.mcp-adapter = {
    enable = lib.mkEnableOption "pi-mcp-adapter — MCP protocol bridge";
    package = lib.mkOption {
      type = lib.types.str;
      default = "npm:pi-mcp-adapter";
      description = "NPM package specifier for this extension.";
    };
  };
}
