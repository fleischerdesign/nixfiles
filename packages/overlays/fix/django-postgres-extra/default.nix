# overlays/fix/django-postgres-extra/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch for django-postgres-extra.
#
# django-postgres-extra derivation specifies version 2.0.9, but .dist-info/METADATA specifies version 2.0.9rc4.
# Python 3.14 metadata check strictly enforces version equality and fails.
# We set dontCheckPythonMetadata = true for django-postgres-extra across all python scopes.
#
# Impact: Blocks Authentik service (features/services/authentik) on host mackaye.
# Remove when upstream nixpkgs fixes version metadata in django-postgres-extra package definition.
_final: prev: {
  python314Packages = prev.python314Packages.overrideScope (
    _pyFinal: pyPrev: {
      django-postgres-extra = pyPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    }
  );
  python3Packages = prev.python3Packages.overrideScope (
    _pyFinal: pyPrev: {
      django-postgres-extra = pyPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    }
  );
  python3 = prev.python3.override {
    packageOverrides = _finalPy: pyPrev: {
      django-postgres-extra = pyPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    };
  };
}
