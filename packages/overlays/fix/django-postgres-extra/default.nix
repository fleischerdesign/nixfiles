# overlays/fix/django-postgres-extra/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch for django-postgres-extra.
#
# django-postgres-extra derivation specifies version 2.0.9, but .dist-info/METADATA specifies version 2.0.9rc4.
# Python 3.14 metadata check strictly enforces version equality and fails.
# We append to pythonPackagesExtensions so all Python interpreters and sub-scopes receive the fix.
#
# Impact: Blocks Authentik service (features/services/authentik) on host mackaye.
# Remove when upstream nixpkgs fixes version metadata in django-postgres-extra package definition.
_final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_pythonFinal: pythonPrev: {
      django-postgres-extra = pythonPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    })
  ];
}
