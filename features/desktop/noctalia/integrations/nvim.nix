# Neovim. The community template renders `matugen.lua` into the writable nvim/lua
# directory, so the plugin and its loader are declared here and the hook never has to
# edit NixVim's generated init.lua. The shell owns the editor's colour scheme; the
# editor's own configured scheme yields to it.
{
  config,
  lib,
  osConfig ? { },
  pkgs,
  ...
}:
let
  cfg = config.my.features.desktop.noctalia;
  # `programs.nixvim` is one submodule option, so reading it back in a condition that this
  # module also defines would be a cycle. The NixOS-side feature option is separate.
  nixvimEnabled = osConfig.my.features.dev.nixvim.enable or false;
in
{
  config = lib.mkIf (cfg.enable && nixvimEnabled) {
    programs.noctalia.settings.theme.templates.community_ids = [ "neovim" ];

    programs.nixvim = {
      colorschemes.vscode.enable = lib.mkForce false;
      extraPlugins = [ pkgs.vimPlugins.base16-nvim ];
      # Post: the generated palette is applied after NixVim's own configuration.
      extraConfigLuaPost = ''
        local ok, matugen = pcall(require, 'matugen')
        if ok then matugen.setup() end
      '';
    };
  };
}
