# overlays/fix/django-tenants/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch.
#
# django-tenants derivation specifies version 3.11.2, but .dist-info/METADATA specifies 3.10.2.
# Python 3.14 metadata check strictly enforces version equality and fails.
# We append to pythonPackagesExtensions so all Python interpreters and sub-scopes receive the fix.
#
# Impact: Blocks Authentik service (features/services/authentik) on host rollins and mackaye.
# Remove when upstream nixpkgs updates pyproject.toml patch or version metadata.
_final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_pythonFinal: pythonPrev: {
      django-tenants = pythonPrev.django-tenants.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    })
  ];
}
