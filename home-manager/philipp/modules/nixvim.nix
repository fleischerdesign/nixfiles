{ pkgs, ... }:

{
  programs.nixvim = {
    enable = true;
    viAlias = true;
    vimAlias = true;

    plugins = {
      # LSP (Language Server Protocol) für Code-Intelligenz
      lsp = {
        enable = true;
        # Definiere die Sprachserver, die du verwenden möchtest
        servers = {
          # Für TypeScript/JavaScript
          tsserver.enable = true;
          # Für HTML
          html.enable = true;
          # Für CSS
          cssls.enable = true;
          # Für JSON
          jsonls.enable = true;
        };
      };
      cmp = {
        enable = true;
        autoEnableSources = true;
        settings.sources = [
          { name = "nvim_lsp"; } # Vorschläge vom Language Server
          { name = "path"; } # Pfadvorschläge
          { name = "buffer"; } # Vorschläge aus dem aktuellen Buffer
        ];
      };
      lualine.enable = true;
      gitsigns.enable = true;
      neo-tree.enable = true;
    };
  };
}
