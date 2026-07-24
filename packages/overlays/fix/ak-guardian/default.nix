# overlays/fix/ak-guardian/default.nix
# TEMPORARY FIX — Python 3.14 pythonMetadataCheckPhase version mismatch for internal authentik packages.
#
# ak-guardian, django-channels-postgres, etc. are internal subpackages in the authentik source tree.
# Authentik derivation specifies versions that mismatch internal pyproject.toml files (e.g. 3.2.0 vs 2026.5.3).
# Python 3.14 metadata check strictly enforces version equality and fails.
# We override fetchFromGitHub in authentik so internal subpackages receive pyproject.toml version patches matching derivation versions.
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
