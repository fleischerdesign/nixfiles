# The plugin catalogue is a directory of plugins, one per folder, discovered by its `plugin.nix`
# marker. The identifier is the folder name: a plugin does not restate its own name, and nix-openclaw
# derives the package attribute (`openclaw-runtime-plugin-<id>`) and the generated lock file
# (`<id>.nix`) from that same name.
#
# The loader is this file, inside the feature that consumes it. The discovery primitive is the shared
# `lib/discovery.nix`, reused rather than reimplemented - the same `findNamed` the feature already uses
# for profile modules. A plugin file is a plain attribute set; an unknown field fails evaluation, so a
# plugin that needs more than the contract must extend the contract here instead of growing silently.
{
  lib,
  # Overridable so a check can point the same loader at a deliberately malformed fixture and prove it
  # fails. The feature always uses the default.
  dir ? ./plugins,
}:
let
  discovery = import ../../../lib/discovery.nix { inherit lib; };
  allowedContributions = [
    "provider"
    "webSearch"
    "tool"
    "harness"
  ];

  # A `plugin.nix` not inside a plugin folder would take `plugins` as its identifier, which is the
  # loader itself; reject it rather than admit a nameless entry.
  pluginDirectories = discovery.findNamed "plugin.nix" dir;

  record =
    path:
    let
      id = builtins.baseNameOf (builtins.dirOf path);
      entry = import path;
      unknownFields = builtins.attrNames (
        builtins.removeAttrs entry [
          "npm"
          "contribution"
        ]
      );
    in
    assert lib.assertMsg (id != "plugins") (
      "plugin discovery: ${toString path} is not inside a plugin directory"
    );
    assert lib.assertMsg (entry ? npm && builtins.isString entry.npm && entry.npm != "") (
      "plugin ${id}: \"npm\" must be a non-empty string"
    );
    assert lib.assertMsg (entry ? contribution && builtins.elem entry.contribution allowedContributions)
      ("plugin ${id}: \"contribution\" must be one of ${lib.concatStringsSep ", " allowedContributions}");
    assert lib.assertMsg (unknownFields == [ ]) (
      "plugin ${id}: unknown field(s) ${lib.concatStringsSep ", " unknownFields}; extend the contract in plugins.nix"
    );
    {
      name = id;
      inherit (entry) npm contribution;
    };

  pairs = map (
    path:
    let
      value = record path;
    in
    {
      inherit (value) name;
      inherit value;
    }
  ) pluginDirectories;
  result = builtins.listToAttrs pairs;
in
# `deepSeq` forces every record, so a malformed plugin fails at evaluation instead of waiting for the
# one consumer that happens to read its field.
builtins.deepSeq result result
