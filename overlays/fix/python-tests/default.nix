_: prev: {
  pythonPackagesExtensions = prev.pythonPackagesExtensions ++ [
    (_: pprev: {
      django = pprev.django.overrideAttrs (_: {
        doCheck = false;
      });
      watchfiles = pprev.watchfiles.overrideAttrs (_: {
        doCheck = false;
      });
      inline-snapshot = pprev.inline-snapshot.overrideAttrs (_: {
        doCheck = false;
      });
      websockets = pprev.websockets.overrideAttrs (_: {
        doCheck = false;
      });
      esptool = pprev.esptool.overrideAttrs (_: {
        doCheck = false;
      });
    })
  ];
}
