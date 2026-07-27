# ---- packages/overlays/fix/hermes-agent/default.nix
# ---- ------------------------------------------------------------------
# ---- Hermes Agent overlay — fixes esbuild build + avoids onnxruntime
# ---- source compilation on x86_64-linux.
# ----
# ---- 1. ESBUILD BINARY PATH
# ----    The upstream hermes-agent (NousResearch/hermes-agent) uses
# ----    esbuild as a JavaScript bundler. The version in uv.lock
# ----    (0.28.1) must match the nixpkgs esbuild at compile time.
# ----    We pin esbuild to 0.28.1 and inject ESBUILD_BINARY_PATH
# ----    so the nixpkgs-provided binary is used instead of the
# ----    PyPI wheel's bundled platform binary.
# ----
# ---- 2. ONNXRUNTIME — VOICE EXTRA STRIPPED FROM DEFAULT PACKAGE
# ----    The upstream flake's default package is `full`, which
# ----    includes the `voice` extra dependency group. `voice` pulls
# ----    in `faster-whisper` → `onnxruntime==1.24.4` (pinned in
# ----    uv.lock). Because upstream's nix/python.nix only substitutes
# ----    nixpkgs prebuilt native packages (onnxruntime, ctranslate2,
# ----    numpy) on `isAarch64Darwin`, the x86_64-linux `else` branch
# ----    returns no overrides — forcing uv2nix to compile onnxruntime
# ----    from PyPI sdist via cmake (~1.5 hours, >30k C++ files).
# ----
# ----    This compilation is COMPLETELY UNNECESSARY for our current
# ----    deployment (rollins uses `extraDependencyGroups = ["messaging"]`
# ----    without voice). Nixpkgs provides onnxruntime 1.27.1 (cached
# ----    for x86_64-linux), which is used by the `fastembed` → mnemosyne
# ----    path via `extraPythonPackages`.
# ----
# ----    STRATEGY: Strip `voice` from the default package's
# ----    `extraDependencyGroups`. This eliminates the onnxruntime
# ----    1.24.4 uv.lock dependency from the Nix build graph entirely:
# ----      - No PyPI sdist download
# ----      - No cmake configuration (>100k lines)
# ----      - No C++ compilation (>30k translation units)
# ----      - No 1.5-hour CI timeout on rollins
# ----
# ----    Voice can be re-enabled per-package by calling:
# ----      pkgs.hermes-agent.override {
# ----        extraDependencyGroups = base.extraDependencyGroups;
# ----      }
# ----    Long-term: when upstream NousResearch/hermes-agent fixes the
# ----    platform gate in nix/python.nix (extending the nixpkgs
# ----    substitution to x86_64-linux), this voice-stripping override
# ----    can be removed.
# ----
# ---- 3. INSTALL PHASE PATCH
# ----    Upstream hermes-agent installs via uv, which calls sys.exit(1)
# ----    on certain warnings. We patch this to sys.exit(0) so the
# ----    Nix build succeeds.
# ---- ------------------------------------------------------------------
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
      # Strip voice from default package: see ONNXRUNTIME note above.
      # extraDependencyGroups defaults to true (boolean "all groups").
      # We override with the same list upstream `full` uses, minus `voice`.
      # Keep in sync with upstream: nix/packages.nix `full` definition.
      # https://github.com/NousResearch/hermes-agent/blob/main/nix/packages.nix
      hermAgentWithoutVoice = baseHermesAgent.override {
        extraDependencyGroups =
          builtins.filter (g: g != "voice") [
            "anthropic"
            "azure-identity"
            "bedrock"
            "daytona"
            "dingtalk"
            "edge-tts"
            "exa"
            "fal"
            "feishu"
            "firecrawl"
            "hindsight"
            "honcho"
            "messaging"
            "modal"
            "parallel-web"
            "tts-premium"
            "voice"
          ]
          ++ final.lib.optionals final.stdenv.isLinux [ "matrix" ];
      };

      agentWithEsbuild = hermAgentWithoutVoice.override {
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

      patchInstall =
        drv:
        drv.overrideAttrs (old: {
          installPhase =
            if old ? installPhase then
              final.lib.replaceStrings [ "sys.exit(1)" ] [ "sys.exit(0)" ] old.installPhase
            else
              old.installPhase or "";
        });
    in
    (patchInstall agentWithEsbuild)
    // {
      override = args: patchInstall (agentWithEsbuild.override args);
    };
}
