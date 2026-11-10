# Declarative extensions use OpenChamber's built-in catalog; runtime installs keep their own catalog.
{
  lib,
  pkgs,
  upstream,
}:
let
  entries = builtins.readDir ./plugins;
  names = lib.attrNames (lib.filterAttrs (_: kind: kind == "directory") entries);
  plugins = map (
    name:
    let
      source = builtins.path {
        path = ./plugins + "/${name}";
        name = "openchamber-plugin-${name}";
      };
      manifest = builtins.fromJSON (builtins.readFile (source + "/package.json"));
      id = "openchamber-builtin-${name}";
    in
    if
      builtins.match "[a-z][a-z0-9-]*" name == null
      || (manifest.openchamber.contributes.panel.id or null) != id
    then
      throw "OpenChamber: plugins/${name}/package.json must declare openchamber.contributes.panel.id = ${id}, using lowercase letters, digits and hyphens"
    else
      { inherit name source id; }
  ) names;
  registry = pkgs.writeText "openchamber-builtins.json" (
    builtins.toJSON {
      version = 1;
      extensions = map (plugin: {
        inherit (plugin) id;
        directory = plugin.name;
      }) plugins;
    }
  );
  original = upstream.openchamber;
  core = original.passthru.core.overrideAttrs (old: {
    postInstall = (old.postInstall or "") + ''
      root="$out/lib/openchamber/packages/web/server/built-in-extensions"
      mkdir -p "$root"
      cp ${registry} "$root/registry.json"
      cd "$out/lib/openchamber"
      ${lib.concatMapStringsSep "\n" (plugin: ''
        cp -R ${plugin.source} "$root/${plugin.name}"
      '') plugins}
      ${pkgs.bun}/bin/bun ${
        builtins.path {
          path = ./validate-plugins.mjs;
          name = "validate-openchamber-plugins.mjs";
        }
      } "$out/lib/openchamber" "$root"
    '';
  });
  server = original.overrideAttrs (old: {
    installPhase =
      builtins.replaceStrings [ (toString original.passthru.core) ] [ (toString core) ]
        old.installPhase;
    passthru = old.passthru // {
      inherit core;
    };
  });
  desktop = upstream.openchamber-desktop.override { openchamberCore = core; };
in
{
  inherit server desktop;
  opencode = upstream.opencode-cli;
}
