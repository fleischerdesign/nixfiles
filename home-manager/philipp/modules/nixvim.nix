{ lib, pkgs, config, ... }:

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
		
		    colorschemes.catppuccin.enable = true;
    		plugins.lualine.enable = true;
    };
  };
}
