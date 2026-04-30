final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      cryptography = python-prev.cryptography.overrideAttrs (old: rec {
        version = "47.0.0";
        src = prev.fetchFromGitHub {
          owner = "pyca";
          repo = "cryptography";
          rev = version;
          hash = "sha256-XmTsD5vVFi+q9gf5lMqro5OcWhgRX573cc4gUozA1Hs=";
        };
        cargoDeps = prev.rustPlatform.fetchCargoVendor {
          inherit src;
          pname = "cryptography";
          inherit version;
          hash = "sha256-RpNSJ4WKnKtqzR1qs223DAM4i0etb4ddL1lZ+PeduVU=";
        };
      });

      cryptography-vectors = python-prev.cryptography-vectors.overrideAttrs (old: rec {
        version = "47.0.0";
        src = prev.fetchFromGitHub {
          owner = "pyca";
          repo = "cryptography";
          rev = version;
          hash = "sha256-XmTsD5vVFi+q9gf5lMqro5OcWhgRX573cc4gUozA1Hs=";
        };
        postPatch = "";
      });
    })
  ];
}
