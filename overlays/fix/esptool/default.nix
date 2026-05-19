_: prev: {
  esptool = prev.esptool.overrideAttrs (_: {
    doCheck = false;
  });
}
