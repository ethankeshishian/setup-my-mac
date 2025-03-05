#!/bin/bash

# System settings (dock, menu bar, trackpad)
defaults write com.apple.dock orientation right
defaults write com.apple.dock autohide-delay -int 0
defaults write com.apple.dock autohide-time-modifier -float 0.4
defaults write com.apple.dock wvous-bl-corner -int 4
defaults write com.apple.dock wvous-br-modifier -int 1048576
defaults write com.apple.dock show-recents -bool FALSE
killall Dock
defaults write NSGlobalDomain _HIHideMenuBar -bool true
defaults write com.apple.AppleMultitouchTrackpad DragLock -bool false # three finger drag
defaults write com.apple.AppleMultitouchTrackpad Dragging -bool false
defaults write com.apple.AppleMultitouchTrackpad TrackpadThreeFingerDrag -bool true
defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true # tap to click
defaults write com.apple.AppleMultitouchTrackpad Clicking -bool true
/System/Library/PrivateFrameworks/SystemAdministration.framework/Resources/activateSettings -u
defaults write -g NSWindowShouldDragOnGesture -bool true # drag window with ctrl + cmd

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
echo -e '\n' >> ~/.zshrc

# Zsh behavior
echo '# zsh behavior
bindkey -v "^?" backward-delete-char
KEYTIMEOUT=1' >> ~/.zshrc

# Software
brew install --cask mos # for smooth scrolling with mouse
brew install --cask mac-mouse-fix@2 # v2 is free for life, v3 is not
cp ./config/mmf/config.plist ~/Library/Application\ Support/com.nuebling.mac-mouse-fix/
brew install --cask betterdisplay # allows monitor brightness control from keyboard
brew install --cask alt-tab # will need to be manually configured
brew install --cask logi-options+
brew install --cask raycast
/usr/libexec/PlistBuddy ~/Library/Preferences/com.apple.symbolichotkeys.plist \
  -c "Delete :AppleSymbolicHotKeys:64" \
  -c "Add :AppleSymbolicHotKeys:64:enabled bool false" \
  -c "Add :AppleSymbolicHotKeys:64:value:parameters array" \
  -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 65535" \
  -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 49" \
  -c "Add :AppleSymbolicHotKeys:64:value:parameters: integer 1048576" \
  -c "Add :AppleSymbolicHotKeys:64:type string standard"
/usr/libexec/PlistBuddy ~/Library/Preferences/com.apple.symbolichotkeys.plist \
  -c "Delete :AppleSymbolicHotKeys:65" \
  -c "Add :AppleSymbolicHotKeys:65:enabled bool false" \
  -c "Add :AppleSymbolicHotKeys:65:value:parameters array" \
  -c "Add :AppleSymbolicHotKeys:65:value:parameters: integer 65535" \
  -c "Add :AppleSymbolicHotKeys:65:value:parameters: integer 49" \
  -c "Add :AppleSymbolicHotKeys:65:value:parameters: integer 1572864" \
  -c "Add :AppleSymbolicHotKeys:65:type string standard"
brew install --cask nikitabobko/tap/aerospace
brew tap FelixKratz/formulae
brew install borders
cp -f ./config/.aerospace.toml ~/
brew install --cask karabiner-elements
cp -f ./config/karabiner.json ~/.config/karabiner/

# Applications
brew install --cask spotify
brew install --cask arc
brew install --cask todoist
brew install --cask obsidian
brew install --cask clay
brew install --cask notion-calendar
brew install --cask visual-studio-code
