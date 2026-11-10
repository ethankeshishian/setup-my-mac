# This Mac's own zsh setup. Shared settings live in ~/.config/zsh/common.zsh; anything below overrides them. Installers may append here.

export NVM_DIR="$HOME/.nvm"
  [ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \. "/opt/homebrew/opt/nvm/nvm.sh"  # This loads nvm
  [ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm"  # This loads nvm bash_completion

export PATH="/Applications/Tailscale.app/Contents/MacOS:$PATH"

[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh

# Activate `fnm`: https://github.com/Schniz/fnm
if command -v fnm >/dev/null; then
    eval "$(fnm env --use-on-cd)"
fi

# Activate `direnv`: https://direnv.net/
if command -v direnv >/dev/null; then
    eval "$(direnv hook zsh)"
fi

# Source the Nix environment.
if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
elif [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

[ -f "/Users/ethankeshishian/.ghcup/env" ] && . "/Users/ethankeshishian/.ghcup/env" # ghcup-env

# bindkey              '^I' menu-select
# bindkey "$terminfo[kcbt]" menu-select
#
# # all Tab widgets
# zstyle ':autocomplete:*complete*:*' insert-unambiguous yes
#
# # all history widgets
# zstyle ':autocomplete:*history*:*' insert-unambiguous yes
#
# # ^S
# zstyle ':autocomplete:menu-search:*' insert-unambiguous yes

# Created by `pipx` on 2026-06-05 20:18:27
export PATH="$PATH:/Users/ethankeshishian/.local/bin"
