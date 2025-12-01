# setup-my-mac

This script is meant to setup my Mac. The goal is to provide a setup for homebrew, zsh, Neovim, kitty, productivity software, and applications.

## Currently experimenting
Zsh config. You will be able to remove certain installs from the shell installation. I added vivid and fzf, which you will need.

## Before install:
- Follow the instructions [here](https://docs.github.com/en/get-started/git-basics/caching-your-github-credentials-in-git) to set up your personal access token. This will let you use Git and clone your nvim config.

## After install:

- Run `:MasonInstallAll` in nvim.
- You might need to run treesitter commands manually: `:TSInstall typescript`,`:TSInstall javascript`, `:TSInstall tsx`
- Run `<leader>I` in tmux. Reload with `<leader>r`.
- At least one of the system config commands will require a logout, if not a full restart.
- Manually disable Control arrow shortcuts in Mac Keyboard Shortcut settings. This makes jumping to panes and windows work for tmux/nvim.
- Manually create Alt-Tab and Raycast shortcuts (configs don't exist).
