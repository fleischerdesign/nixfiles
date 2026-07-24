# overlays/fix/django-tenants/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch.
#
# django-tenants derivation specifies version 3.11.2, but .dist-info/METADATA specifies 3.10.2.
# django-postgres-extra derivation specifies version 2.0.9, but .dist-info/METADATA specifies 2.0.9rc4.
# Python 3.14 metadata check strictly enforces version equality and fails.
#
# Impact: Blocks Authentik service (features/services/authentik) on host rollins and mackaye.
# Remove when upstream nixpkgs updates pyproject.toml patch or version metadata.
_final: prev: {
  python314Packages = prev.python314Packages.overrideScope (
    _pyFinal: pyPrev: {
      django-tenants = pyPrev.django-tenants.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
      django-postgres-extra = pyPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    }
  );
  python3Packages = prev.python3Packages.overrideScope (
    _pyFinal: pyPrev: {
      django-tenants = pyPrev.django-tenants.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
      django-postgres-extra = pyPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    }
  );
}
