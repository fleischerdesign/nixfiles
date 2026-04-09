# Temporary fix for openapi-generator-cli hash mismatch.
# This overrides fetchpatch globally to catch the broken 23326.patch 
# even when used in nested derivations like maven-deps.
# Upstream PR: https://github.com/NixOS/nixpkgs/pull/507558
self: super: {
  fetchpatch = arg: 
    let
      oldHash = "sha256-s68VoIXSFGvGCaFtCUYkeoq+CgC+2gIdDIIsmn8uqyk=";
      newHash = "sha256-E1VgtaIW1V+8ch2RpW850fVNl5Iqitjog+0b8DKFgZw=";
      # The correct commit URL from the upstream PR fix
      newUrl = "https://github.com/OpenAPITools/openapi-generator/commit/ff66e1bc7fe33dcee89de7296eb7bcd5e2a11cc6.patch";
      
      isThePatch = builtins.isAttrs arg && (
        (arg ? hash && arg.hash == oldHash) || 
        (arg ? sha256 && arg.sha256 == oldHash)
      );
    in
    if isThePatch then
      super.fetchpatch ((builtins.removeAttrs arg [ "hash" "sha256" ]) // { 
        url = newUrl; 
        hash = newHash;
      })
    else
      super.fetchpatch arg;
}
