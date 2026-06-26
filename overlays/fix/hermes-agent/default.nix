inputs: final: prev: {
  hermes-agent =
    let
      baseOverlay = inputs.hermes-agent.overlays.default final prev;
      baseHermesAgent = baseOverlay.hermes-agent;
    in
    baseHermesAgent.override {
      callPackage =
        fn: args:
        let
          drv = final.callPackage fn args;
        in
        if builtins.isAttrs drv && drv ? overrideAttrs then
          drv.overrideAttrs (_: {
            ESBUILD_BINARY_PATH = "${final.esbuild}/bin/esbuild";
          })
        else
          drv;
    };
}
