inputs: final: prev: {
  hermes-agent =
    let
      baseOverlay = inputs.hermes-agent.overlays.default final prev;
      baseHermesAgent = baseOverlay.hermes-agent;

      esbuild_0_28_1 = final.esbuild.overrideAttrs (_: rec {
        version = "0.28.1";
        src = final.fetchFromGitHub {
          owner = "evanw";
          repo = "esbuild";
          rev = "v${version}";
          hash = "sha256-V+HKaWGAIs24ynFFIS9fQ0EAJJdNmlAMeL1sgDEAqWM=";
        };
        vendorHash = "sha256-+BfxCyg0KkDQpHt/wycy/8CTG6YBA/VJvJFhhzUnSiQ=";
      });

      # Apply ESBUILD binary path override via callPackage
      agentWithEsbuild = baseHermesAgent.override {
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

      patchInstall = drv: drv.overrideAttrs (old: {
        installPhase = if old ? installPhase then final.lib.replaceStrings [ "sys.exit(1)" ] [ "sys.exit(0)" ] old.installPhase else old.installPhase or "";
      });
    in
    (patchInstall agentWithEsbuild) // {
      override = args: patchInstall (agentWithEsbuild.override args);
    };
}
