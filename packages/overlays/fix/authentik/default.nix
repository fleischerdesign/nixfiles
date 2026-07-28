_final: prev:

let
  #
  # Part 1: Authentik monorepo sub-packages
  #
  # pythonMetadataCheckHook (nixpkgs PR #532778, Jul 2026) checks that the
  # derivation version matches the package metadata in .dist-info/METADATA.
  #
  # Authentik is a monorepo: the nixpkgs derivation uses version = "2026.5.3"
  # (the monorepo release tag), but individual Python sub-packages have their
  # own versions in pyproject.toml:
  #   ak-guardian                → 3.2.0
  #   django-channels-postgres   → 0.1.0
  #   django-dramatiq-postgres   → 0.1.0
  #   django-postgres-cache      → 0.1.0
  #
  # Fix: create a patched copy of the monorepo source where the
  # pyproject.toml versions match the derivation version. Inject it
  # via fetchFromGitHub override — it is an overrideable argument of
  # the authentik derivation and is called exactly once to create `src`.
  # All sub-packages inherit the same src via the let binding.

  patched-src = prev.runCommand "authentik-src" { } ''
    cp -r ${prev.authentik.src} $out
    chmod -R +w $out

    substituteInPlace $out/packages/ak-guardian/pyproject.toml \
      --replace-fail 'version = "3.2.0"' \
                      'version = "2026.5.3"'

    substituteInPlace $out/packages/django-channels-postgres/pyproject.toml \
      --replace-fail 'version = "0.1.0"' \
                      'version = "2026.5.3"'

    substituteInPlace $out/packages/django-dramatiq-postgres/pyproject.toml \
      --replace-fail 'version = "0.1.0"' \
                      'version = "2026.5.3"'

    substituteInPlace $out/packages/django-postgres-cache/pyproject.toml \
      --replace-fail 'version = "0.1.0"' \
                      'version = "2026.5.3"'
  '';

  #
  # Part 2: Non-monorepo dependencies with version mismatches
  #
  # Several nixpkgs Python packages in the authentik dependency tree have
  # derivation versions that don't match the upstream .dist-info/METADATA:
  #   django-postgres-extra  → 2.0.9 vs 2.0.9rc4
  #   django-tenants         → 3.11.2 vs 3.10.2
  #   (potentially more)
  #
  # pythonPackagesExtensions (all-packages.nix line 4580) is applied BEFORE
  # packageOverrides in passthrufun.nix and survives every python.override
  # call — unlike overlay-based python3Packages modifications, which are
  # stripped by authentik's internal python314.override.
  #
  # Strategy: wrap buildPythonPackage so only matching packages get
  # dontCheckPythonMetadata set. Non-matching packages pass through
  # to the original python-prev.buildPythonPackage unchanged → identical
  # derivation hashes → cache hits for all other packages.

  # Known non-monorepo dependencies in the authentik dependency tree
  # where the derivation version doesn't match the upstream package
  # metadata version. Add to this list when new ones are discovered.
  knownMetadataMismatches = [
    "authentik-django" # pname "authentik-django" != METADATA "authentik"
    "django-postgres-extra" # 2.0.9 vs 2.0.9rc4
    "django-tenants" # 3.11.2 vs 3.10.2
  ];

  extensions = prev.pythonPackagesExtensions ++ [
    (_python-final: python-prev: {
      buildPythonPackage =
        attrs:
        let
          pkg = python-prev.buildPythonPackage attrs;
          pname = attrs.pname or "";
        in
        if builtins.elem pname knownMetadataMismatches then
          pkg.overrideAttrs (old: {
            env = (old.env or { }) // {
              dontCheckPythonMetadata = "1";
            };
          })
        else
          pkg;
    })
  ];

in
{
  authentik = prev.authentik.override {
    fetchFromGitHub = _attrs: patched-src;
  };

  pythonPackagesExtensions = extensions;
}
