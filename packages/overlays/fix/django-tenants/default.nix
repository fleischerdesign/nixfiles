# overlays/fix/django-tenants/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch.
#
# django-tenants derivation specifies version 3.11.2, but .dist-info/METADATA specifies 3.10.2.
# Python 3.14 metadata check strictly enforces version equality and fails.
#
# Impact: Blocks Authentik service (features/services/authentik) on host rollins and mackaye.
# Remove when upstream nixpkgs updates pyproject.toml patch or version metadata.
_final: prev: {
  python314 = prev.python314.override (old: {
    packageOverrides = prev.lib.composeExtensions (old.packageOverrides or (_: _: { })) (
      _pyFinal: pyPrev: {
        django-tenants = pyPrev.django-tenants.overridePythonAttrs (_: {
          dontCheckPythonMetadata = true;
        });
      }
    );
  });
  python3 = prev.python3.override (old: {
    packageOverrides = prev.lib.composeExtensions (old.packageOverrides or (_: _: { })) (
      _pyFinal: pyPrev: {
        django-tenants = pyPrev.django-tenants.overridePythonAttrs (_: {
          dontCheckPythonMetadata = true;
        });
      }
    );
  });
}
