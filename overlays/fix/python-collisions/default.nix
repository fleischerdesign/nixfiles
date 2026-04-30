final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      django-tenants = python-prev.django-tenants.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${prev.python3.sitePackages}/docs || true
        '';
      });
      cryptography = python-prev.cryptography.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${prev.python3.sitePackages}/docs || true
        '';
      });
      moto = python-prev.moto.overrideAttrs (old: {
        doCheck = false;
      });
      websockets = python-prev.websockets.overrideAttrs (old: {
        doCheck = false;
      });
    })
  ];
}
