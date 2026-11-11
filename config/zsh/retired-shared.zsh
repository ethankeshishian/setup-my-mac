# Lines that common.zsh used to contain, in their old form. Nothing sources this file.
# `smm setup` strips these from an existing ~/.zshrc when seeding a new host's file, so
# old copies don't reload plugins twice or override newer shared settings. When you
# change or remove a line in common.zsh, add its old form here.
export LS_COLORS="$(vivid generate catppuccin-mocha)"
zinit light zsh-users/zsh-completions
zinit light zsh-users/zsh-syntax-highlighting
zinit light zsh-users/zsh-autosuggestions
zinit light Aloxaf/fzf-tab
zinit snippet OMZL::git.zsh
zinit snippet OMZP::git
zinit snippet OMZP::sudo
zinit snippet OMZP::archlinux
zinit snippet OMZP::aws
zinit snippet OMZP::kubectl
zinit snippet OMZP::kubectx
zinit snippet OMZP::command-not-found
autoload -Uz compinit && compinit
eval "$(fzf --zsh)"
eval "$(zoxide init --cmd cd zsh)"
eval "$(pay-respects zsh --alias fuck)"
eval $(thefuck --alias)
bindkey -M viins '\e\x7f' backward-kill-word
zstyle ':completion:*' menu no
HISTSIZE=5000
HISTDUP=erase
setopt appendhistory
setopt sharehistory
setopt hist_ignore_dups
setopt inc_append_history
alias ls="ls --color"
zstyle ':fzf-tab:complete:cd:*' fzf-preview 'ls --color $realpath'
zstyle ':fzf-tab:complete:__zoxide_z:*' fzf-preview 'ls --color $realpath'
