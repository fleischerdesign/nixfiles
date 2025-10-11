# SPDX-License-Identifier: MIT
{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true; # Sets vim as the default editor
    viAlias = true;      # Creates a vi alias to vim
    vimAlias = true;     # Creates a vim alias to nvim

    globals.mapleader = " ";

    opts = {
          updatetime = 100;
          number = true;
          relativenumber = true;
	  shiftwidth = 2;

    };

    # Nixvim plugins
    plugins = {
      # Which-key shows available keybindings
      which-key.enable = true;

      # Icons for file types
      web-devicons.enable = true;

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
          # Python
          pyright.enable = true;
          # Rust
                    rust_analyzer = {
            enable = true;
            installCargo = true;
            installRustc = true;
          };
          # C/C++
          clangd.enable = true;
          # TypeScript, React
          ts_ls.enable = true;
          # Vue
          vue_ls.enable = true;
          # Nix
          nil_ls.enable = true;
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
