# lib/extra-settings.nix
# Typed `extraSettings` escape hatch.
#
# Restricts values to flat scalars because the `//` merge with real
# options would silently drop nested attrs/lists anyway.  When used
# with `mkCheckShadowing` it also warns about keys that shadow
# existing options (at eval time, not runtime).
#
# Usage:
#   let piLib = import ../../lib/extra-settings.nix { inherit lib; };
#   in {
#     options.extraSettings = lib.mkOption (
#       (piLib.scalarExtraSettings) // { default = {}; }
#     );
#     config.assertions = piLib.mkCheckShadowing
#       "my.features.dev.pi.extensions.foo"
#       [ "workflow" "chromeProfile" ]
#       config;
#   }

{ lib }:

let
  scalarType = lib.types.oneOf [
    lib.types.str
    lib.types.int
    lib.types.bool
  ];
in

{
  scalarExtraSettings = {
    type = lib.types.attrsOf scalarType;
    description = "Additional JSON config keys — flat scalars only (no nested objects or lists).";
  };

  mkCheckShadowing =
    pathName: knownKeys: cfg:
    let
      extra = lib.attrByPath (lib.splitString "." pathName ++ [ "extraSettings" ]) { } cfg;
      shadowed = builtins.filter (k: builtins.elem k knownKeys) (builtins.attrNames extra);
    in
    lib.optionals (shadowed != [ ]) [
      {
        assertion = false;
        message = "Option ${pathName}.extraSettings contains key(s) that shadow real options: ${builtins.concatStringsSep ", " shadowed}. Remove them — they are silently ignored.";
      }
    ];
}
