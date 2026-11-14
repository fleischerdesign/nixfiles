# Backport upstream #194540; only the Gateway needs the inference-policy repair.
# The build refuses both an already-fixed package and an unfamiliar call shape.
{ openclaw-gateway }:
let
  patcher = builtins.path {
    path = ./prepare-worker-search-policy.mjs;
    name = "openclaw-prepare-worker-search-policy.mjs";
  };
in
openclaw-gateway.overrideAttrs (previous: {
  # nix-openclaw's npm package disables fixup; patch the installed Gateway graph,
  # not the sealed worker archive. NODE_BIN is its own pinned Node runtime.
  installPhase = ''
    ${previous.installPhase}
    "$NODE_BIN" ${patcher} "$out/lib/node_modules/openclaw"
  '';
})
