final: prev:
let
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
in
{
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pfinal: pprev: {
      cryptography_vectors = pprev.buildPythonPackage {
        pname = "cryptography-vectors";
        inherit version src;
        pyproject = true;
        sourceRoot = "${src.name}/vectors";
        build-system = [ pprev.uv-build ];
        doCheck = false;
        pythonImportsCheck = [ "cryptography_vectors" ];
      };

      cryptography =
        (pprev.cryptography.override {
          "cryptography-vectors" = pfinal.cryptography_vectors;
        }).overrideAttrs
          (old: {
            inherit version src cargoDeps;
          });
    })
  ];
}
