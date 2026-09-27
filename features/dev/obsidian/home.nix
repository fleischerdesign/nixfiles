# features/dev/obsidian/home.nix - the per-user half of the Obsidian feature.
{
  config,
  lib,
  pkgs,
  osConfig ? { },
  ...
}:
let
  # The system side owns the options; the user side reads them, so the same declaration feeds both.
  sys = osConfig.my.features.dev.obsidian;

  mkPluginFromManifest =
    manifestPath:
    let
      m = builtins.fromJSON (builtins.readFile manifestPath);
      tag = "${m.upstream.tagPrefix or ""}${m.version}";
    in
    pkgs.stdenv.mkDerivation {
      pname = m.pname;
      version = m.version;
      srcs = [
        (pkgs.fetchurl {
          url = "https://github.com/${m.upstream.owner}/${m.upstream.repo}/releases/download/${tag}/main.js";
          sha256 = m.mainHash;
        })
        (pkgs.fetchurl {
          url = "https://github.com/${m.upstream.owner}/${m.upstream.repo}/releases/download/${tag}/manifest.json";
          sha256 = m.manifestHash;
        })
      ]
      ++ lib.optionals (m.stylesHash or "" != "") [
        (pkgs.fetchurl {
          url = "https://github.com/${m.upstream.owner}/${m.upstream.repo}/releases/download/${tag}/styles.css";
          sha256 = m.stylesHash;
        })
      ];
      dontUnpack = true;
      installPhase = ''
        mkdir -p $out
        for src in $srcs; do
          cp $src $out/$(stripHash $src)
        done
      '';
    };

  obsidianLiveSyncPkg = mkPluginFromManifest ./plugins/livesync/manifest.json;
  obsidianTemplaterPkg = mkPluginFromManifest ./plugins/templater/manifest.json;
  obsidianDataviewPkg = mkPluginFromManifest ./plugins/dataview/manifest.json;
  obsidianLinterPkg = mkPluginFromManifest ./plugins/linter/manifest.json;
  obsidianMetaBindPkg = mkPluginFromManifest ./plugins/meta-bind/manifest.json;
in
{
  programs.obsidian = {
    enable = true;
    cli.enable = true;

    vaults.${sys.vaultName} = {
      target = sys.vaultTarget;
      settings = {
        communityPlugins =
          lib.optionals sys.livesync.enable [
            {
              pkg = obsidianLiveSyncPkg;
            }
          ]
          ++ lib.optionals sys.plugins.templater [ obsidianTemplaterPkg ]
          ++ lib.optionals sys.plugins.dataview [ obsidianDataviewPkg ]
          ++ lib.optionals sys.plugins.linter [ obsidianLinterPkg ]
          ++ lib.optionals sys.plugins.metaBind [ obsidianMetaBindPkg ];
      };
    };
  };

  home.file."${sys.vaultTarget}/.obsidian/plugins/obsidian-livesync/data.json" =
    lib.mkIf sys.livesync.enable
      {
        source = config.lib.file.mkOutOfStoreSymlink "/run/secrets/rendered/obsidian_livesync_data.json";
      };
}
