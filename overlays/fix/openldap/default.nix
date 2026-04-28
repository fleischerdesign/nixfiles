final: prev: {
  openldap = prev.openldap.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
}
