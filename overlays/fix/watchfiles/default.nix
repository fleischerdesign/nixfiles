_: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pprev: {
      watchfiles = pprev.watchfiles.overrideAttrs (_: {
        doCheck = false;
      });
    })
  ];
}
