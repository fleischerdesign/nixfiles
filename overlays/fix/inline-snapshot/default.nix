_: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pprev: {
      inline-snapshot = pprev.inline-snapshot.overrideAttrs (_: {
        doCheck = false;
      });
    })
  ];
}
