final: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (pfinal: pprev: {
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
