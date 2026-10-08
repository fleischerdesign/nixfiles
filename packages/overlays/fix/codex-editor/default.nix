_final: prev: {
  vscode-marketplace = prev.vscode-marketplace // {
    openai = prev.vscode-marketplace.openai // {
      # Codex itself is static. The extension's native voice and shell helpers
      # need NixOS loader paths while retaining the marketplace-owned version.
      chatgpt = prev.vscode-marketplace.openai.chatgpt.overrideAttrs (old: {
        nativeBuildInputs = (old.nativeBuildInputs or [ ]) ++ [ prev.autoPatchelfHook ];
        buildInputs = (old.buildInputs or [ ]) ++ [
          prev.stdenv.cc.cc.lib
          prev.ncurses
        ];
      });
    };
  };
}
