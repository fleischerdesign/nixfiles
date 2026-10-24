# Prove every inline declaration in the fleet output before it reaches the
# daemon.
#
# The constructors in `lib/nod.nix` type the projection; this check proves the
# *output*: schema, shape, unique ids and derivation rules. A file-backed
# declaration is out of scope — the daemon parses it when it reads the file.
{
  pkgs,
  lib,
  self,
  ...
}:
let
  providers = self.nod.providers or { };
  # A derivation (a rendered file) is an attrset too; only a document with
  # `resources` or `schema` is an inline declaration.
  declarations = lib.mapAttrs (_: provider: provider.desired) (
    lib.filterAttrs (
      _: provider:
      let
        desired = provider.desired or null;
      in
      builtins.isAttrs desired && (desired ? resources || desired ? schema)
    ) providers
  );

  isText = value: builtins.isString value && value != "";
  isResource =
    entry:
    builtins.isAttrs entry
    && isText (entry.kind or "")
    && isText (entry.id or "")
    && builtins.isAttrs (entry.attributes or null);

  checkDeclaration =
    name: desired:
    let
      schema = desired.schema or 1;
      resources = desired.resources or null;
      absent = desired.absent or [ ];
      derive = desired.derive or [ ];
      list = value: if builtins.isList value then value else [ ];
      all = list resources ++ list absent;
      keys = map (entry: "${entry.kind}/${entry.id}") (builtins.filter isResource all);
      duplicates = lib.filter (key: lib.count (other: other == key) keys > 1) (lib.unique keys);
      badResources = builtins.filter (entry: !isResource entry) all;
      validRule =
        rule:
        builtins.isAttrs rule
        && isText (rule.id or "")
        && builtins.isAttrs (rule.from or null)
        && isText (rule.from.kind or "")
        && isText (rule.from.id or "")
        && isText (rule.from.attribute or "")
        && builtins.isAttrs (rule.template or null)
        && isText (rule.template.kind or "")
        && isText (rule.template.id or "");
    in
    lib.optional (!builtins.isInt schema || schema < 1 || schema > 2) "${name}: schema must be 1 or 2"
    ++
      lib.optional (!builtins.isList resources)
        "${name}: `resources` must be a list, got ${builtins.typeOf resources}; keys: ${builtins.concatStringsSep "," (builtins.attrNames desired)}"
    ++ lib.optional (!builtins.isList absent) "${name}: `absent` must be a list"
    ++ lib.optional (!builtins.isList derive) "${name}: `derive` must be a list"
    ++ lib.optional (schema < 2 && list derive != [ ]) "${name}: `derive` requires schema 2"
    ++ map (entry: "${name}: invalid resource ${builtins.toJSON entry}") badResources
    ++ map (key: "${name}: duplicate resource ${key}") duplicates
    ++ map (rule: "${name}: invalid derivation ${builtins.toJSON rule}") (
      builtins.filter (rule: !validRule rule) (list derive)
    );

  problems = lib.concatLists (lib.mapAttrsToList checkDeclaration declarations);
in
if problems != [ ] then
  throw "nod declaration error:\n  ${lib.concatStringsSep "\n  " problems}"
else
  pkgs.runCommandLocal "nod-declaration-check" { } ''
    echo "inline declarations: ${toString (builtins.length (builtins.attrNames declarations))}" > "$out"
  ''
