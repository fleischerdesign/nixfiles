{
  pkgs,
  ...
}:

pkgs.buildNpmPackage rec {
  pname = "self-hosted-livesync-cli";
  version = "1.0.2";

  src = pkgs.fetchFromGitHub {
    owner = "vrtmrz";
    repo = "obsidian-livesync";
    rev = version;
    hash = "sha256-nkM7VTuO5xMLHEXLYmiHXUq5Nfc67Pd5HMnV7WE4XbU=";
  };

  npmDepsHash = "sha256-r4x3sk+CUCMr992wuznpE3zNRaFdDZLxDtaMNV7Wjj0=";

  postBuild = ''
    cd src/apps/cli && ../../../node_modules/.bin/vite build && cd ../../..
  '';

  nativeBuildInputs = [ pkgs.makeWrapper ];

  postInstall = ''
    mkdir -p $out/lib/node_modules/obsidian-livesync/src/apps/cli/dist
    cp -r src/apps/cli/dist/* $out/lib/node_modules/obsidian-livesync/src/apps/cli/dist/
    mkdir -p $out/bin
    makeWrapper ${pkgs.nodejs}/bin/node $out/bin/livesync-cli \
      --add-flags "$out/lib/node_modules/obsidian-livesync/src/apps/cli/dist/index.cjs"
  '';
}
