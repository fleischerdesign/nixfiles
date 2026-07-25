# extensions/pi-lens/default.nix
# pi-lens: LSP diagnostics, tree-sitter, ast-grep, code quality.
# No global config — linter/formatter config is project-level (biome.json, ruff.toml).

{ lib, ... }:
{
  options.my.features.dev.pi.extensions.pi-lens = {
    enable = lib.mkEnableOption "pi-lens — real-time code diagnostics and structural analysis";
  };
}
