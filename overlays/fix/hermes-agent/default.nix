inputs: final: prev: {
  hermes-agent =
    let
      baseOverlay = inputs.hermes-agent.overlays.default final prev;
      baseHermesAgent = baseOverlay.hermes-agent;

      esbuild_0_28_1 = final.esbuild.overrideAttrs (old: rec {
        version = "0.28.1";
        src = final.fetchFromGitHub {
          owner = "evanw";
          repo = "esbuild";
          rev = "v${version}";
          hash = "sha256-V+HKaWGAIs24ynFFIS9fQ0EAJJdNmlAMeL1sgDEAqWM=";
        };
        vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
      });
    in
    baseHermesAgent.override {
      callPackage =
        fn: args:
        let
          drv = final.callPackage fn args;
        in
        if builtins.isAttrs drv && drv ? overrideAttrs then
          drv.overrideAttrs (_: {
            ESBUILD_BINARY_PATH = "${esbuild_0_28_1}/bin/esbuild";
          })
        else
          drv;
    };
}
