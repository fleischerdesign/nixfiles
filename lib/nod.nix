# Constructors for a nod desired-state document.
#
# The document is data: resources, tombstones and derivations. A flake output
# carries it as a value; a configuration file names it as a path. This module
# builds the value and refuses duplicate ids, which the core would otherwise
# reject only after a plan.
{ lib }:
rec {
  # One resource, with the shape the provider protocol expects.
  resource = kind: id: attributes: { inherit kind id attributes; };

  # The declaration document: schema 2, unique (kind, id) pairs across
  # resources and tombstones. A resource cannot be both declared and absent.
  desired =
    {
      resources,
      absent ? [ ],
      derive ? [ ],
    }:
    let
      all = resources ++ absent;
      keys = map (entry: "${entry.kind}/${entry.id}") all;
      duplicates = lib.filter (key: lib.count (other: other == key) keys > 1) (lib.unique keys);
    in
    if duplicates != [ ] then
      throw "nod declaration error: duplicate resource(s) ${lib.concatStringsSep ", " duplicates}"
    else
      {
        schema = 2;
        inherit resources absent;
      }
      // lib.optionalAttrs (derive != [ ]) { inherit derive; };
}
