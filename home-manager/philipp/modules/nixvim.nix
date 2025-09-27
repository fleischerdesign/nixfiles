{ lib, config, ... }:

let
  cfg = config.my.homeManager.modules.nixvim;
in
{
	config = lib.mkIf cfg.enable {
	programs.nixvim = {
    	enable = true;
    	defaultEditor = true;
    	viAlias = true;
    	vimAlias = true;

		globals = {
			mapleader = " ";
		};

		opts = {
            updatetime = 100;
			relativenumber = true;
			number = true;
			hidden = true;
			undofile = true;
			scrolloff = 8;
			wrap = false;

			tabstop = 4;
			shiftwidth = 4;
			autoindent = true;
		};

		lsp = {
            servers = {
              bashls.enable = true;
			  ts_ls.enable = true;
			  nil_ls.enable = true;
			  html.enable = true;
			  tailwindcss.enable = true;
			  vue_ls.enable = true;
			  cssls.enable = true;
			  clangd.enable = true;
			  rust_analyzer.enable = true;
			  gopls.enable = true;
			  marksman.enable = true;
			  eslint.enable = true;
			};
		};
		    colorschemes.catppuccin.enable = true;
		plugins = {
			lspconfig.enable = true;
			lualine.enable = true;
			treesitter.enable = true;
			web-devicons.enable = true;
			telescope.enable = true;
cmp = {
	enable = true;
  autoEnableSources = true;
  settings = {
  	sources = [
    	{ name = "nvim_lsp"; }
    	{ name = "path"; }
    	{ name = "buffer"; }
  	];
    mapping = {
      # Navigiere zum nächsten/vorherigen Eintrag
      "<C-n>" = "cmp.mapping.select_next_item()";
      "<C-p>" = "cmp.mapping.select_prev_item()";

      # Schließe das Menü
      "<C-e>" = "cmp.mapping.abort()";

      # Bestätige die Auswahl mit Enter
      "<CR>" = "cmp.mapping.confirm({ select = true })";

      # Blättere durch die Dokumentation des Vorschlags
      "<C-d>" = "cmp.mapping.scroll_docs(-4)";
      "<C-u>" = "cmp.mapping.scroll_docs(4)";
    };
	};
  };
		};

		keymaps = [
    {
      mode = "n"; # Normal-Modus
      key = "<leader>ff";
      action = "<cmd>Telescope find_files<cr>";
      options.desc = "Find Files"; # Beschreibung, die später angezeigt werden kann
    }
    {
      mode = "n";
      key = "<leader>fg";
      action = "<cmd>Telescope live_grep<cr>";
      options.desc = "Find Text (Live Grep)";
    }
    {
      mode = "n";
      key = "<leader>fb";
      action = "<cmd>Telescope buffers<cr>";
      options.desc = "Find Buffers";
    }
  ];
    };
  };
}
