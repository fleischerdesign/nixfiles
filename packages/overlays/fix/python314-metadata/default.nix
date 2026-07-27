# overlays/fix/python314-metadata/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase failures across nixpkgs.
#
# Python 3.14 introduced strict importlib.metadata version and name checks.
# Several packages (cheetah3 for sabnzbd; django-tenants, django-postgres-extra, ak-guardian, authentik-django for authentik)
# fail this check due to mismatches between derivation metadata and pyproject.toml / dist-info.
#
# Impact: Fixes SABnzbd (strummer) and Authentik (rollins, mackaye).
# Remove when upstream nixpkgs updates version metadata in these derivations.
_final: prev: {
  pythonPackagesExtensions = (prev.pythonPackagesExtensions or [ ]) ++ [
    (_pythonFinal: pythonPrev: {
      cheetah3 = pythonPrev.cheetah3.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
      django-tenants = pythonPrev.django-tenants.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
      django-postgres-extra = pythonPrev.django-postgres-extra.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
      ak-guardian = pythonPrev.ak-guardian.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
      authentik-django = pythonPrev.authentik-django.overridePythonAttrs (_: {
        dontCheckPythonMetadata = true;
      });
    })
  ];

  authentik = prev.authentik.override (_: {
    fetchFromGitHub =
      args:
      prev.runCommand "authentik-src-patched" { } ''
        cp -r ${prev.fetchFromGitHub args} $out
        chmod -R +w $out
        if [ -f $out/pyproject.toml ]; then
          sed -i 's/^name = "authentik"/name = "authentik-django"/' $out/pyproject.toml
          echo -e '\n[tool.hatch.build.targets.wheel]\npackages = ["authentik"]' >> $out/pyproject.toml
        fi
        if [ -f $out/packages/ak-guardian/pyproject.toml ]; then
          sed -i 's/^version = .*/version = "2026.5.3"/' $out/packages/ak-guardian/pyproject.toml
        fi
        if [ -f $out/packages/django-channels-postgres/pyproject.toml ]; then
          sed -i 's/^version = .*/version = "2026.5.3"/' $out/packages/django-channels-postgres/pyproject.toml
        fi
        if [ -f $out/packages/django-dramatiq-postgres/pyproject.toml ]; then
          sed -i 's/^version = .*/version = "2026.5.3"/' $out/packages/django-dramatiq-postgres/pyproject.toml
        fi
        if [ -f $out/packages/django-postgres-cache/pyproject.toml ]; then
          sed -i 's/^version = .*/version = "2026.5.3"/' $out/packages/django-postgres-cache/pyproject.toml
        fi
      '';
  });
}
