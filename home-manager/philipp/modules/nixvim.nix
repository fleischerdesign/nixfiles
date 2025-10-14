# SPDX-License-Identifier: MIT
{
  config,
  lib,
  pkgs,
  ...
}:
lib.mkIf config.my.homeManager.modules.nixvim.enable {
  programs.nixvim = {
    enable = true;
    defaultEditor = true; # Sets vim as the default editor
    viAlias = true; # Creates a vi alias to vim
    vimAlias = true; # Creates a vim alias to nvim

    globals = {
      mapleader = " ";
    };

    highlight = {
      Normal = {
	bg = "NONE";
	ctermbg = "NONE";
      };

      NonText = {
	bg = "NONE";
	ctermbg = "NONE";
      };
    };

    opts = {
      updatetime = 100;
      number = true;
      relativenumber = true;
      shiftwidth = 2;
      cmdheight = 0;
      fillchars = {
	eob = " ";
      };
    };

    # Nixvim plugins
    plugins = {
      nvim-tree.enable = true;

      fugitive.enable = true;

      # Which-key shows available keybindings
      which-key.enable = true;

      # Icons for file types
      web-devicons.enable = true;

      lualine = {
	enable = true;
	settings = {
	  extensions = [ "nvim-tree" ];
	};
      };

      # Telescope for fuzzy finding
      telescope = {
        enable = true;
        settings = {

          defaults = {
            mappings = {
              # Mappings für den Einfügemodus (während du tippst)
              i = {
                "<C-j>" = "move_selection_next";
                "<C-k>" = "move_selection_previous";
              };
              # (Optional, aber nützlich) Mappings für den Normalmodus (wenn du Esc drückst)
              n = {
                "j" = "move_selection_next";
                "k" = "move_selection_previous";
              };
            };
          };
        };
      };

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
      {
        key = "<leader>fm"; # fm für "format"
        action = "<cmd>lua vim.lsp.buf.format()<cr>";
        options = {
          noremap = true;
          silent = true;
          desc = "Format with LSP";
        };
      }
      {
        mode = [
          "n"
          "v"
          "o"
        ];
        key = "ö";
        action = "[";
      }
      {
        mode = [
          "n"
          "v"
          "o"
        ];
        key = "ä";
        action = "]";
      }
      {
        mode = [
          "n"
          "v"
          "o"
        ];
        key = "ü";
        action = "{";
      }
      # Man könnte auch ß für } nehmen, wenn gewünscht
      {
        mode = [
          "n"
          "v"
          "o"
        ];
        key = "ß";
        action = "}";
      }
      {
        key = "<leader>e";
        action = "<cmd>NvimTreeToggle<cr>";
        options.desc = "Toggle file explorer";
      }

      # Öffnet den Dateibaum und hebt die aktuell geöffnete Datei hervor.
      # Sehr nützlich, um zu sehen, wo eine Datei im Projekt liegt.
      {
        key = "<leader>f"; # 'f' für 'find'
        action = "<cmd>NvimTreeFindFile<cr>";
        options.desc = "Find current file in explorer";
      }

      #Remap search commands
      {
	key = "-";
	action = "/";
      }
      {
	key = "_";
	action = "?";
      }
    ];
  };
}
