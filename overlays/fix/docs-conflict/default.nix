_: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pprev: {
      cryptography = pprev.cryptography.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${prev.python3.sitePackages}/docs
        '';
      });
      django-tenants = pprev.django-tenants.overrideAttrs (old: {
        postInstall = (old.postInstall or "") + ''
          rm -rf $out/${prev.python3.sitePackages}/docs
        '';
      });
    })
  ];
}
