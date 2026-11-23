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
      openchamber = manifest.openchamber or { };
      panelId = openchamber.contributes.panel.id or null;
      id = openchamber.id or panelId;
      expected = "openchamber-builtin-${name}";
    in
    if builtins.match "[a-z][a-z0-9-]*" name == null then
      throw "OpenChamber: plugins/${name} must use a lowercase name with letters, digits and hyphens"
    else if (openchamber.apiVersion or null) != 1 then
      throw "OpenChamber: plugins/${name}/package.json must declare openchamber.apiVersion = 1"
    else if id == null then
      throw "OpenChamber: plugins/${name}/package.json must declare openchamber.id (or contributes.panel.id)"
    else if id != expected then
      throw "OpenChamber: plugins/${name}/package.json must declare openchamber.id = ${expected}"
    else if panelId != null && panelId != id then
      throw "OpenChamber: plugins/${name}/package.json declares different openchamber.id and contributes.panel.id"
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
  mergeRegistry = builtins.path {
    path = ./merge-registry.py;
    name = "merge-openchamber-registry.py";
  };
  patchLimitFailover = builtins.path {
    path = ./patch-limit-failover.py;
    name = "patch-openchamber-limit-failover.py";
  };
  # Upstream overrides installPhase; this stdenv does not run postInstall for a custom phase, so
  # append the extension injection here rather than relying on the hook.
  core = original.passthru.core.overrideAttrs (old: {
    postPatch = (old.postPatch or "") + ''
      ${pkgs.python3}/bin/python ${patchLimitFailover} .
    '';
    installPhase = old.installPhase + ''
      root="$out/lib/openchamber/packages/web/build/server/built-in-extensions"
      mkdir -p "$root"
      ${pkgs.python3}/bin/python ${mergeRegistry} "$root/registry.json" ${registry}
      cd "$out/lib/openchamber"
      ${lib.concatMapStringsSep "\n" (plugin: ''
        if [ -e "$root/${plugin.name}" ]; then
          echo "OpenChamber: built-in extension directory already exists: ${plugin.name}" >&2
          exit 1
        fi
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
      let
        patched =
          builtins.replaceStrings [ (toString original.passthru.core) ] [ (toString core) ]
            old.installPhase;
      in
      if patched == old.installPhase then
        throw "OpenChamber: server installPhase no longer references the overridden core"
      else
        patched;
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
