#!/bin/bash

# General
if ! command -v brew &> /dev/null; then
  /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
fi
if [ -z "$HOMEBREW_PREFIX" ]; then
  export HOMEBREW_PREFIX="/opt/homebrew" # This is for M1 Macs
  echo 'export HOMEBREW_PREFIX="/opt/homebrew"' >> ~/.zshrc
fi
brew install python
brew tap homebrew/cask-fonts
brew install --cask "font-martian-mono-nerd-font"

# Terminal (kitty)
brew install --cask kitty
kitten themes catppuccin-mocha
cp -f ./config/kitty.conf ~/.config/kitty/

# Shell (zsh)
brew install zsh-autocomplete
brew install zsh-autosuggestions
brew install zsh-syntax-highlighting
brew install powerlevel10k
brew install thefuck
cp ./config/.p10k.zsh ~/
echo '# Terminal' >> ~/.zshrc
echo '# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi' >> ~/.zshrc
echo 'source /opt/homebrew/share/powerlevel10k/powerlevel10k.zsh-theme
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
source $HOMEBREW_PREFIX/share/zsh-autocomplete/zsh-autocomplete.plugin.zsh
source $HOMEBREW_PREFIX/share/zsh-autosuggestions/zsh-autosuggestions.zsh
source $HOMEBREW_PREFIX/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
eval $(thefuck --alias)
alias ls="ls --color"' >> ~/.zshrc
echo -e '\n' >> ~/.zshrc

# Neovim
brew install neovim
brew install ripgrep
git clone https://github.com/NvChad/starter ~/.config/nvim
cp -rf ./config/nvim/init.lua ~/.config/nvim/
cp -rf ./config/nvim/lua/* ~/.config/nvim/lua/

# Tmux
brew install tmux
brew install tpm
cp -f ./config/.tmux.conf ~/

# Aliases
echo '# Aliases' >> ~/.zshrc
echo 'alias python=python3
alias pip=pip3
alias nv=nvim
alias vim=nvim' >> ~/.zshrc
