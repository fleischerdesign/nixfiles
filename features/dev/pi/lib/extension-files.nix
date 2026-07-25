# lib/extension-files.nix
# Shared _files submodule type used by every extension that deploys
# runtime config or assets. Extensions never touch home.file directly
# — the orchestrator wires everything from these declarations.
#
# Usage:
#   let piLib = import ../../lib/extension-files.nix { inherit lib; };
#   in {
#     options.my.features.dev.pi.extensions.foo._files =
#       lib.mkOption { type = piLib.filesModule; default = {}; };
#   }

{ lib }:

{
  filesModule = lib.types.submodule {
    options.config = lib.mkOption {
      type = lib.types.attrsOf (lib.types.attrsOf lib.types.anything);
      default = { };
      description = "Extension JSON config files (path → attrs).";
    };
    options.assets = lib.mkOption {
      type = lib.types.attrsOf lib.types.path;
      default = { };
      description = "Extension asset directories (path → source dir).";
    };
  };
}
