_: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pprev: {
      django = pprev.django.overrideAttrs (_: {
        doCheck = false;
      });
    })
  ];
}
