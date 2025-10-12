# SPDX-License-Identifier: MIT
{ pkgs, ... }:
{
  programs.nixvim = {
    enable = true;
    defaultEditor = true; # Sets vim as the default editor
    viAlias = true;      # Creates a vi alias to vim
    vimAlias = true;     # Creates a vim alias to nvim

    globals = {
      mapleader = " ";
    };

    opts = {
          updatetime = 100;
          number = true;
          relativenumber = true;
	  shiftwidth = 2;
      cmdheight = 0;
    };

    extraConfigVim = ''
      set termguicolors
      highlight Normal guibg=NONE ctermbg=NONE
      highlight NonText guibg=NONE ctermbg=NONE
    '';

    # Nixvim plugins
    plugins = {
      fugitive.enable = true;

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
  mapping = {
    # Bestätige einen Vorschlag mit Enter
    "<CR>" = "cmp.mapping.confirm({ select = true })";
    # Navigiere mit Tab und Shift-Tab durch die Vorschläge
    "<Tab>" = "cmp.mapping.select_next_item()";
    "<S-Tab>" = "cmp.mapping.select_prev_item()";
    # Scrolle durch die Dokumentation des Vorschlags
    "<C-d>" = "cmp.mapping.scroll_docs(-4)";
    "<C-f>" = "cmp.mapping.scroll_docs(4)";
  };
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
  {
    key = "<leader>gs";
    action = "<cmd>Git<cr>";
    options.desc = "Git Status";
  }
  {
    key = "<leader>gb";
    action = "<cmd>Git blame<cr>";
    options.desc = "Git Blame";
  }
  {
    key = "gd";
    action = "<cmd>Telescope lsp_definitions<cr>";
    options.desc = "Go to Definition";
  }
  {
    key = "gr";
    action = "<cmd>Telescope lsp_references<cr>";
    options.desc = "Go to References";
  }
  {
    key = "K"; # Großes K
    action = "<cmd>lua vim.lsp.buf.hover()<cr>";
    options.desc = "Show Hover Docs";
  }
  {
    key = "<leader>rn";
    action = "<cmd>lua vim.lsp.buf.rename()<cr>";
    options.desc = "Rename";
  }
    ];
  };
}
