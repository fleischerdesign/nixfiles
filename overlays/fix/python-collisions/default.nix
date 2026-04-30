final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      django-tenants = python-prev.django-tenants.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${python-prev.python.sitePackages}/docs || true
        '';
      });
      cryptography = python-prev.cryptography.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${python-prev.python.sitePackages}/docs || true
        '';
      });
      moto = python-prev.moto.overrideAttrs (old: {
        doCheck = false;
        dontCheck = true;
        pytestCheckPhase = "true";
        checkPhase = "true";
      });
      websockets = python-prev.websockets.overrideAttrs (old: {
        doCheck = false;
        dontCheck = true;
        pytestCheckPhase = "true";
        unittestCheckPhase = "true";
        checkPhase = "true";
      });
    })
  ];
}
