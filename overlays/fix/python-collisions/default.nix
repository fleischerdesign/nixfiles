final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (python-final: python-prev: {
      django-tenants = python-prev.django-tenants.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${prev.python3.sitePackages}/docs
        '';
      });
      cryptography = python-prev.cryptography.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${prev.python3.sitePackages}/docs
        '';
      });
    })
  ];
}
