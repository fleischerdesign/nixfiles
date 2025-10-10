# SPDX-License-Identifier: MIT
{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true; # Sets vim as the default editor
    viAlias = true;      # Creates a vi alias to vim
    vimAlias = true;     # Creates a vim alias to nvim

    # Nixvim plugins
    plugins = {
      # Which-key shows available keybindings
      which-key.enable = true;

      # Lualine for a nice statusline
      lualine.enable = true;

      # Telescope for fuzzy finding
      telescope.enable = true;

      # Treesitter for syntax highlighting
      treesitter.enable = true;

      # LSP for code intelligence
      lsp = {
        enable = true;
        servers = {
          # Add your language servers here
          # Example for python:
          # pyright.enable = true;
        };
      };

      # Autocomplete
      cmp = {
        enable = true;
        settings = {
          sources = [
            { name = "nvim_lsp"; }
            { name = "luasnip"; }
            { name = "buffer"; }
            { name = "path"; }
          ];
        };
      };
    };

    # Keybindings
    keymaps = [
      {
        key = "<leader>ff";
        action = "<cmd>Telescope find_files<cr>";
        options = {
          noremap = true;
          silent = true;
          desc = "Find files";
        };
      }
      {
        key = "<leader>fg";
        action = "<cmd>Telescope live_grep<cr>";
        options = {
          noremap = true;
          silent = true;
          desc = "Live grep";
        };
      }
    ];
  };
}
