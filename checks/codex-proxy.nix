{ pkgs, ... }:
pkgs.runCommandLocal "codex-proxy-check"
  {
    nativeBuildInputs = [ pkgs.codex ];
  }
  ''
    ${pkgs.custom.opencodex}/bin/ocx __keyring-load-check
    ${pkgs.custom.opencodex}/bin/ocx --version
    mkdir -p "$TMPDIR/codex"
    env CODEX_HOME="$TMPDIR/codex" codex --version
    env CODEX_HOME="$TMPDIR/codex" ${pkgs.custom.chatgpt-linux}/lib/chatgpt/resources/codex --version
    ${pkgs.custom.chatgpt-linux}/lib/chatgpt/resources/cua_node/bin/node --version
    env CODEX_HOME="$TMPDIR/codex" ${pkgs.vscode-marketplace.openai.chatgpt}/share/vscode/extensions/openai.chatgpt/bin/linux-x86_64/codex --version
    test -s ${pkgs.custom.opencodex}/lib/opencodex/gui/dist/index.html
    # The full proxy check runs outside the Nix build sandbox: upstream's Codex
    # write coordinator requires a root-owned /tmp, which the sandbox does not provide.
    touch $out
  ''
