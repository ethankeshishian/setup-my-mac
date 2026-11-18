{ pkgs, ... }:
{
  home.file.".config/tmux/plugins/catppuccin/tmux".source =
    "${pkgs.tmuxPlugins.catppuccin}/share/tmux-plugins/catppuccin";
  home.file.".config/tmux/plugins/resurrect".source =
    "${pkgs.tmuxPlugins.resurrect}/share/tmux-plugins/resurrect";
  home.file.".config/tmux/plugins/continuum".source =
    "${pkgs.tmuxPlugins.continuum}/share/tmux-plugins/continuum";
}
