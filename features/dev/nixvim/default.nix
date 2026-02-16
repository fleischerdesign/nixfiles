# features/dev/nixvim.nix
{ config, lib, pkgs, ... }:

let
  cfg = config.my.features.dev.nixvim;
in
{
  options.my.features.dev.nixvim = {
    enable = lib.mkEnableOption "NixVim configuration";
  };

  config = lib.mkIf cfg.enable {
    home-manager.sharedModules = [{
      programs.nixvim = {
        enable = true;
        defaultEditor = true; # Sets vim as the default editor
        viAlias = true; # Creates a vi alias to vim
        vimAlias = true; # Creates a vim alias to nvim

        colorschemes.vscode = {
          enable = true;
          settings = {
            transparent = true;
            italic_comments = true;
          };
        };

        globals = {
          mapleader = " ";
        };

        highlight = {
          # Make indentation lines very subtle (dark grey)
          IblIndent = {
            fg = "#444444";
          };
          IblWhitespace = {
            fg = "#444444";
          };
        };

        opts = {
          updatetime = 100;
          number = true;
          relativenumber = true;
          shiftwidth = 2;
          cmdheight = 0;
          background = "dark"; # Use valid value 'dark'
          signcolumn = "yes"; # Always show the signcolumn to prevent jumping
          clipboard = "unnamedplus"; # Use system clipboard
          fillchars = {
            eob = " ";
          };
        };

        # Extra packages like clipboard providers
        extraPackages = with pkgs; [
          wl-clipboard
        ];

        # Nixvim plugins
        plugins = {
          # Git signs (Visual Git integration)
          gitsigns.enable = true;

          # Easy commenting
          comment.enable = true;

          # Auto-closing brackets
          nvim-autopairs.enable = true;

          # Indentation guides
          indent-blankline = {
            enable = true;
            settings = {
              indent = {
                char = "┊"; # Thinner, dotted character for a subtle look
              };
            };
          };

          # Icons in autocomplete
          lspkind = {
            enable = true;
            settings.cmp = {
              enable = true;
              menu = {
                nvim_lsp = "[LSP]";
                nvim_lua = "[api]";
                path = "[path]";
                luasnip = "[snip]";
                buffer = "[buf]";
              };
            };
          };

          # Better diagnostics list
          trouble.enable = true;

          # Tab-like buffer bar
          bufferline = {
            enable = true;
            settings = {
              options = {
                separator_style = "thick";
                diagnostics = "nvim_lsp";
                offsets = [
                  {
                    filetype = "NvimTree";
                    text = "File Explorer";
                    highlight = "Directory";
                    text_align = "left";
                  }
                ];
              };
            };
          };

          nvim-tree.enable = true;
          fugitive.enable = true;

          # Which-key shows available keybindings
          which-key.enable = true;

          # Icons for file types
          web-devicons.enable = true;

          lualine = {
            enable = true;
            settings = {
              options = {
                theme = "auto";
              };
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
              # QML
              qmlls.enable = true;
              # Java
              jdtls.enable = true;
              # Go
              gopls.enable = true;
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
                # Bestätige einen Vorschlag mit Enter, aber nur wenn er explizit ausgewählt wurde.
                # Das verhindert, dass Enter eine neue Zeile blockiert, wenn das Menü nur offen ist.
                "<CR>" = "cmp.mapping.confirm({ select = false })";
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
              desc = "Telescope find files";
            };
          }
          {
            key = "<leader>fg";
            action = "<cmd>Telescope live_grep<cr>";
            options = {
              noremap = true;
              silent = true;
              desc = "Telescope live grep";
            };
          }
          {
            key = "<leader>fb";
            action = "<cmd>Telescope buffers<cr>";
            options = {
              noremap = true;
              silent = true;
              desc = "Telescope buffers";
            };
          }
          {
            key = "<leader>fh";
            action = "<cmd>Telescope help_tags<cr>";
            options = {
              noremap = true;
              silent = true;
              desc = "Telescope help tags";
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
          {
            key = "<leader>xx";
            action = "<cmd>Trouble diagnostics toggle<cr>";
            options.desc = "Toggle Trouble (Diagnostics)";
          }

          # --- Window Navigation ---
          {
            key = "<C-h>";
            action = "<C-w>h";
            options.desc = "Move to left window";
          }
          {
            key = "<C-j>";
            action = "<C-w>j";
            options.desc = "Move to lower window";
          }
          {
            key = "<C-k>";
            action = "<C-w>k";
            options.desc = "Move to upper window";
          }
          {
            key = "<C-l>";
            action = "<C-w>l";
            options.desc = "Move to right window";
          }

          # --- Buffer Navigation (Bufferline) ---
          {
            key = "<S-h>";
            action = "<cmd>BufferLineCyclePrev<cr>";
            options.desc = "Previous Buffer";
          }
          {
            key = "<S-l>";
            action = "<cmd>BufferLineCycleNext<cr>";
            options.desc = "Next Buffer";
          }
          {
            key = "<leader>bd";
            action = "<cmd>bdelete<cr>";
            options.desc = "Delete current Buffer";
          }
          {
            key = "<leader>bn";
            action = "<cmd>enew<cr>";
            options.desc = "New empty Buffer";
          }

          # --- Utilities ---
          {
            key = "<leader>h";
            action = "<cmd>nohlsearch<cr>";
            options.desc = "Clear search highlights";
          }
        ];

        # Format on Save
        autoCmd = [
          {
            event = "BufWritePre";
            pattern = "*";
            callback = {
              __raw = "function() vim.lsp.buf.format() end";
            };
          }
        ];
      };
    }];
  };
}
