# extensions/context-mode/default.nix
# context-mode: sandboxed code execution, FTS5 knowledge base, intent-driven search.
# No user-authored global config.

{ lib, ... }:
{
  options.my.features.dev.pi.extensions.context-mode = {
    enable = lib.mkEnableOption "context-mode — context window savings engine";
    package = lib.mkOption {
      type = lib.types.str;
      default = "npm:context-mode";
      description = "NPM package specifier for this extension.";
    };
  };
}
