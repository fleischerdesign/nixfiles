{
  self,
}:
_final: prev: {
  authentik = prev.callPackage (self.outPath + "/overlays/fix/authentik/package.nix") { };
}
