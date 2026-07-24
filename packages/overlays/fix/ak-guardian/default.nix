# overlays/fix/ak-guardian/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch for internal authentik packages.
#
# ak-guardian, django-channels-postgres, etc. are internal subpackages in the authentik source tree.
# authentik-django defines pname = "authentik-django" in nix, but pyproject.toml defines name = "authentik".
# Python 3.14 metadata check fails because dist-info metadata name mismatch.
# We override fetchFromGitHub in authentik so all internal subpackages receive pyproject.toml name/version patches.
#
# Impact: Blocks Authentik service (features/services/authentik) on hosts rollins and mackaye.
# Remove when upstream nixpkgs fixes version metadata in authentik package definition.
_final: prev: {
  authentik = prev.authentik.override (old: {
    fetchFromGitHub =
      args:
      prev.runCommand "authentik-src-patched" { } ''
        cp -r ${prev.fetchFromGitHub args} $out
        chmod -R +w $out
        if [ -f $out/authentik/pyproject.toml ]; then
          sed -i 's/^name = .*/name = "authentik-django"/' $out/authentik/pyproject.toml
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
