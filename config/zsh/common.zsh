# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Vars
# Keep PATH and fpath free of duplicates when startup files add the same directory twice.
typeset -U PATH path FPATH fpath
export HOMEBREW_PREFIX="/opt/homebrew"
export EDITOR=nvim

# Source a tool's generated shell setup from a cache instead of running the tool on
# every start. The cache is rebuilt when the tool's resolved binary path changes
# (Nix and Homebrew upgrades change it) or the binary is newer than the cache.
# Usage: _cached_eval <name> <binary> <command...>
_cached_eval() {
  local name=$1 bin=${commands[$2]:A}
  shift 2
  [[ -n $bin ]] || return 0
  local cache=${XDG_CACHE_HOME:-$HOME/.cache}/zsh-eval/$name.zsh stamp="# $bin $*" first=
  [[ -r $cache ]] && read -r first < $cache
  if [[ $first != "$stamp" || $bin -nt $cache ]]; then
    mkdir -p ${cache:h}
    if ! { print -r -- $stamp && "$@" } > $cache.$$ 2>/dev/null || ! mv -f $cache.$$ $cache; then
      # Caching failed, so run the tool directly this time.
      rm -f $cache.$$
      eval "$("$@")"
      return
    fi
  fi
  source $cache
}

_vivid_ls_colors() { print -r -- "export LS_COLORS=${(qq)$(vivid generate catppuccin-mocha)}" }
_cached_eval vivid vivid _vivid_ls_colors

# Set the directory we want to store zinit and plugins
ZINIT_HOME="${XDG_DATA_HOME:-${HOME}/.local/share}/zinit/zinit.git"

# Download Zinit, if it's not there yet
if [ ! -d "$ZINIT_HOME" ]; then
   mkdir -p "$(dirname $ZINIT_HOME)"
   git clone https://github.com/zdharma-continuum/zinit.git "$ZINIT_HOME"
fi

# Source/Load zinit
source "${ZINIT_HOME}/zinit.zsh"

# The prompt loads now. Everything else loads right after the first prompt draws
# (zinit "turbo mode"), in the order listed.
zinit ice depth=1; zinit light romkatv/powerlevel10k

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh

_load_completions() {
  # nix-homebrew doesn't link brew's own completion, so add the copy shipped with brew.
  fpath=(${${:-$HOMEBREW_PREFIX/Library/Homebrew}:A:h:h}/completions/zsh(N/) $fpath)
  # Rebuild the dump at most once a day; `rm ~/.zcompdump` forces a refresh.
  autoload -Uz compinit
  () { if (( $# )); then compinit; else compinit -C; fi } ${ZDOTDIR:-$HOME}/.zcompdump(N.mh+24)
  zinit cdreplay -q
}

# Suggestions are accepted only from insert mode, with Right arrow or Ctrl-E.
# Normal-mode motions like A, $, l and w just move the cursor.
ZSH_AUTOSUGGEST_ACCEPT_WIDGETS=(forward-char end-of-line)
ZSH_AUTOSUGGEST_PARTIAL_ACCEPT_WIDGETS=(forward-word emacs-forward-word)

# Starting a program is slow on this Mac because security software checks every launch.
# fzf-tab starts cat, dd and rm on each Tab; swap them for zsh built-ins so fzf is the
# only program it starts. Each swap applies only while fzf-tab's line matches exactly,
# so an fzf-tab update can only undo the speedup, never break Tab.
_fzf_tab_use_builtins() {
  zmodload zsh/system 2>/dev/null && zmodload -F zsh/files b:zf_rm 2>/dev/null || return 0
  # zinit wraps autoloaded functions in a loader stub, so define it from fzf-tab's source.
  [[ -r $FZF_TAB_HOME/lib/-ftb-fzf ]] || return 0
  functions[-ftb-fzf]=$(<$FZF_TAB_HOME/lib/-ftb-fzf)
  REPLY=${functions[-ftb-fzf]}
  _replace_literal 'cat > $tmp_dir/completions.$$' \
    '{ local _ftb_buf; while sysread _ftb_buf; do syswrite -- "$_ftb_buf"; done } > $tmp_dir/completions.$$'
  _replace_literal '$(command "$dd" bs=1G count=1 status=none iflag=nonblock < /dev/tty 2>/dev/null)' \
    '$(_fzf_tab_typeahead)'
  _replace_literal 'command rm $tmp_dir/*.$$ 2> /dev/null' 'zf_rm -f -- $tmp_dir/*.$$(N)'
  functions[-ftb-fzf]=$REPLY
}
# Replaces the first exact occurrence of <old> in $REPLY with <new>; no-op if absent.
_replace_literal() {
  local i=${REPLY[(i)${(b)1}*]}
  (( i <= $#REPLY )) && REPLY=${REPLY[1,i-1]}$2${REPLY[i+$#1,-1]}
}
# Keys typed after Tab but before the picker opens become its search query, without
# starting dd. Reads whatever is waiting on the terminal and doesn't block.
_fzf_tab_typeahead() {
  local buf typed fd
  { exec {fd}</dev/tty } 2>/dev/null || return 0
  while sysread -t 0 -i $fd buf 2>/dev/null; do typed+=$buf; done
  exec {fd}<&-
  print -rn -- $typed
}
# fzf waits 100ms after Esc in case it starts a longer key sequence; 10ms is plenty locally.
export ESCDELAY=10

# Completion definitions and snippets go before compinit. fzf-tab loads after compinit
# and before widget wrappers; fzf's Tab handler wraps fzf-tab; syntax highlighting goes last.
zinit wait lucid for \
    zsh-users/zsh-completions \
    OMZL::git.zsh \
    OMZP::git \
    OMZP::sudo \
  atinit'_load_completions' atload'_fzf_tab_use_builtins; _cached_eval fzf fzf fzf --zsh' \
    Aloxaf/fzf-tab \
  atload'!_zsh_autosuggest_start' \
    zsh-users/zsh-autosuggestions \
    zsh-users/zsh-syntax-highlighting

# Aliases
alias python=python3
alias pip=pip3
alias nv=nvim
alias vim=nvim
alias switch='git town switch'
alias sp='git town set-parent'
alias c='clear'
# --nocnf: no "command not found" handler. Handlers that search for a package to install
# delay zsh's plain "command not found" message by hundreds of milliseconds.
_cached_eval pay-respects pay-respects pay-respects zsh --alias fuck --nocnf
# eza lists with icons, and `ll` shows each file's git status. eza's -t needs a field
# (`ls -l -s modified`); `command ls` is the plain one.
if (( $+commands[eza] )); then
  alias ls='eza --icons=auto --group-directories-first'
  alias ll='ls -la --git'
  alias lt='ls --tree --level=2'
else
  alias ls='ls --color'
fi

# zsh behavior
bindkey -v "^?" backward-delete-char
KEYTIMEOUT=1
# Option-Backspace deletes like macOS text fields: punctuation and spaces go with the word
# before them. a/b/c -> a/b/ -> a/ -> (empty).
_backward_kill_mac_word() {
  local WORDCHARS=''
  zle backward-kill-word
}
zle -N _backward_kill_mac_word
bindkey -M viins '\e\x7f' _backward_kill_mac_word
# Plain forward-char/end-of-line here, so these accept suggestions while vi-mode motions don't.
bindkey -M viins '^[[C' forward-char '^[OC' forward-char '^E' end-of-line
# Cmd-Backspace (Ghostty sends Ctrl-U) clears the whole line in either mode.
bindkey -M viins '^U' kill-whole-line
bindkey -M vicmd '^U' kill-whole-line
# Cmd-Z undoes the last edit (Ghostty sends Ctrl-_ for it).
bindkey -M viins '^_' undo
bindkey -M vicmd '^_' undo
# `_` jumps to the first character, as in Vim.
bindkey -M vicmd '_' vi-first-non-blank
# Ctrl-X opens the whole command in nvim, from either mode; save and quit to put the edited
# command back on the line. This replaces pay-respects' Ctrl-X Ctrl-X; `fuck` still works.
autoload -Uz edit-command-line
zle -N edit-command-line
# edit-command-line edits only the selection when one is active, so drop it first.
_edit_whole_command() {
  REGION_ACTIVE=0
  zle edit-command-line
}
zle -N _edit_whole_command
bindkey -M viins '^X' _edit_whole_command
bindkey -M vicmd '^X' _edit_whole_command
#zsh history
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward
HISTSIZE=1000000
HISTFILE=~/.zsh_history
SAVEHIST=$HISTSIZE
# share_history also writes each command immediately, so inc_append_history would conflict.
setopt share_history
setopt hist_ignore_space
setopt hist_ignore_all_dups
setopt hist_save_no_dups
setopt hist_find_no_dups
# zsh completion styling
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Za-z}'
zstyle ':completion:*' list-colors "${(s.:.)LS_COLORS}"
# `menu yes` makes Tab open the fzf-tab picker straight away; `menu no` would insert
# the shared prefix first.
zstyle ':completion:*' menu yes
# Say so right away when nothing matches.
zstyle ':completion:*:warnings' format '%F{red}no matches%f'
# In the picker, Tab picks the highlighted entry; Up and Down move.
zstyle ':fzf-tab:*' fzf-bindings 'tab:accept'
# Big repos have tens of thousands of remote branches and tags. Offer recent and local
# branches first; remote branches, tags, commits and files only when nothing local matches.
zstyle ':completion:*:*:git-(checkout|switch):*' tag-order \
  'tree-ishs heads heads-local recent-branches branches' \
  'heads-remote commit-tags commit-objects remote-branch-names-noprefix modified-files'
zstyle ':fzf-tab:complete:(cd|__zoxide_z):*' fzf-preview 'eza -1 --icons --color=always $realpath 2>/dev/null || ls --color $realpath'
# Git completions preview what you're picking: a file's changes, or a branch's recent commits.
# Previews start after the picker draws, so they never slow it down.
_git_pick_preview='
if [[ -e $word ]]; then
  if git ls-files --error-unmatch -- $word >/dev/null 2>&1; then
    git diff --color=always HEAD -- $word | { delta --width=$FZF_PREVIEW_COLUMNS 2>/dev/null || cat; }
  else
    bat --color=always --style=numbers -- $word 2>/dev/null || eza -1 --icons --color=always $word 2>/dev/null || ls --color $word
  fi
else
  for ref in $word origin/$word; do
    git log --color=always -40 --format="%C(yellow)%h%C(reset) %s %C(dim)%cr · %an%C(reset)" $ref -- 2>/dev/null && break
  done
fi
'
zstyle ':fzf-tab:complete:git-(checkout|switch|cherry-pick|rebase|merge|reset|log|show|add|diff|restore|rm):*' \
  fzf-preview $_git_pick_preview
zstyle ':fzf-tab:complete:git-stash-*:*' fzf-preview \
  'git stash show -p --include-untracked --color=always $word 2>/dev/null | { delta --width=$FZF_PREVIEW_COLUMNS 2>/dev/null || cat; }'
# Short lists still get room for a useful preview.
zstyle ':fzf-tab:complete:git-*:*' fzf-min-height 15
unset _git_pick_preview

# fzf keys: Ctrl-T inserts a path, Ctrl-R searches history, Option-C jumps to a folder.
# Paths come from fd, which skips .git and anything gitignored (build output, Nix `result`
# links). Previews show a file's contents or a folder's tree; long history entries wrap.
export FZF_CTRL_T_COMMAND='fd --hidden --exclude .git --strip-cwd-prefix'
export FZF_ALT_C_COMMAND='fd --type d --hidden --exclude .git --strip-cwd-prefix'
_fzf_tree_preview='{ eza --tree --level=2 --icons --color=always {} 2>/dev/null || ls --color {}; } | head -200'
export FZF_CTRL_T_OPTS="--preview 'if [[ -d {} ]]; then $_fzf_tree_preview; else bat --color=always --style=numbers --line-range=:300 {} 2>/dev/null || head -300 {}; fi'"
export FZF_ALT_C_OPTS="--preview '$_fzf_tree_preview'"
unset _fzf_tree_preview
export FZF_CTRL_R_OPTS='--wrap'

# Shell integrations. fzf's keybindings load with fzf-tab above.
# zoxide's doctor warns when lines follow its init; installers append to the host file, so the warning is a false alarm.
export _ZO_DOCTOR=0
_cached_eval zoxide zoxide zoxide init --cmd cd zsh
