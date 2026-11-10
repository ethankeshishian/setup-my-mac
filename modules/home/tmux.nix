{ pkgs, ... }:
{
  home.file.".config/tmux/plugins/catppuccin/tmux".source =
    "${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin";
}
