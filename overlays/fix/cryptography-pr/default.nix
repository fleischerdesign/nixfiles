final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pfinal: pprev: {
      cryptography = pprev.cryptography.overrideAttrs (old: rec {
        version = "47.0.0";
        src = prev.fetchFromGitHub {
          owner = "pyca";
          repo = "cryptography";
          tag = version;
          hash = "sha256-XmTsD5vVFi+q9gf5lMqro5OcWhgRX573cc4gUozA1Hs=";
        };
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          inherit src;
          pname = "cryptography";
          inherit version;
          hash = "sha256-RpNSJ4WKnKtqzR1qs223DAM4i0etb4ddL1lZ+PeduVU=";
        };
        postPatch = ''
          substituteInPlace pyproject.toml \
            --replace-fail "--benchmark-disable" ""
        '';
      });

      cryptography_vectors = pprev.buildPythonPackage {
        pname = "cryptography-vectors";
        inherit (pfinal.cryptography) version src;
        pyproject = true;
        sourceRoot = "source/vectors";
        build-system = [ pprev.uv-build ];
        doCheck = false;
        pythonImportsCheck = [ "cryptography_vectors" ];
        meta = pprev.cryptography_vectors.meta;
      };
    })
  ];
}
