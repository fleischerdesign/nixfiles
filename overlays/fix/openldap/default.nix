_: prev: {
  openldap = prev.openldap.overrideAttrs (_: {
    doCheck = !prev.stdenv.hostPlatform.isi686;
  });
}
