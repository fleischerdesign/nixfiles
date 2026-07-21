# packages/custom/default.nix
# Automatic Overlay loader for all custom package derivations under packages/custom/*/default.nix
_: prev: {
  custom =
    let
      customDir = ./.;
      entries = builtins.readDir customDir;
      pkgDirs = prev.lib.filterAttrs (
        name: type:
        type == "directory" && builtins.pathExists (customDir + "/${name}/default.nix")
      ) entries;
    in
    prev.lib.mapAttrs (
      name: _: prev.callPackage (customDir + "/${name}") { }
    ) pkgDirs;
}
