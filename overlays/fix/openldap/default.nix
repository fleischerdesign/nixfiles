final: prev: {
  openldap = prev.openldap.overrideAttrs (oldAttrs: {
    doCheck = !prev.stdenv.hostPlatform.isI686;
  });
}
