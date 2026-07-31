_final: prev:

let
  # Authentik monorepo sub-packages version fix:
  # pythonMetadataCheckHook checks that derivation version matches package metadata in .dist-info/METADATA.
  # Authentik monorepo uses version 2026.5.3, but sub-packages have 3.2.0 / 0.1.0 in pyproject.toml.
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

  knownMetadataMismatches = [
    "authentik-django" # pname "authentik-django" != METADATA "authentik"
    "django-postgres-extra" # 2.0.9 vs 2.0.9rc4
    "django-tenants" # 3.11.2 vs 3.10.2
  ];

  # Override __functor on python-prev.buildPythonPackage (which is a functor attrset)
  extensions = prev.pythonPackagesExtensions ++ [
    (_python-final: python-prev: {
      buildPythonPackage =
        python-prev.buildPythonPackage // {
          __functor =
            _self: attrs:
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
        };
    })
  ];

in
{
  authentik = prev.authentik.override {
    fetchFromGitHub = _attrs: patched-src;
  };

  pythonPackagesExtensions = extensions;
}
