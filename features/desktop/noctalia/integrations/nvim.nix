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
    # The upstream community template is not selected: its apply hook appends a loader to
    # ~/.config/nvim/init.lua, which Home Manager owns. The vendored template renders the
    # same module without a hook, and the plugin and loader are declared below.
    my.features.desktop.noctalia.settings.theme.templates.user.nvim_base16 = {
      input_path = "${../templates/neovim-base16.lua}";
      output_path = "$XDG_CONFIG_HOME/nvim/lua/matugen.lua";
    };

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
