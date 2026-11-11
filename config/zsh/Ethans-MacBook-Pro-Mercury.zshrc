# This Mac's own zsh setup. Shared settings live in ~/.config/zsh/common.zsh; anything below overrides them. Installers may append here.
[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh

export PATH="/Applications/Tailscale.app/Contents/MacOS:$PATH"

# Activate `fnm`: https://github.com/Schniz/fnm
if command -v fnm >/dev/null; then
    eval "$(fnm env --use-on-cd)"
fi

# Activate `direnv`: https://direnv.net/
if command -v direnv >/dev/null; then
    _cached_eval direnv direnv direnv hook zsh
fi

# Source the Nix environment.
if [[ -f "$HOME/.nix-profile/etc/profile.d/nix.sh" ]]; then
    . "$HOME/.nix-profile/etc/profile.d/nix.sh"
elif [[ -f /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]]; then
    . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
fi

[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env" # ghcup-env

# Created by `pipx` on 2026-06-05 20:18:27
export PATH="$PATH:$HOME/.local/bin"
