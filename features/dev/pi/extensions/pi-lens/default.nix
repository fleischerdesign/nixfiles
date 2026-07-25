# extensions/pi-lens/default.nix
# pi-lens: LSP diagnostics, tree-sitter, ast-grep, code quality.
# No global config — linter/formatter config is project-level (biome.json, ruff.toml).

{ lib, ... }:
{
  options.my.features.dev.pi.extensions.pi-lens = {
    enable = lib.mkEnableOption "pi-lens — real-time code diagnostics and structural analysis";
    package = lib.mkOption {
      type = lib.types.str;
      default = "npm:pi-lens";
      description = "NPM package specifier for this extension.";
    };
  };
}
