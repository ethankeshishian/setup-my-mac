# This Mac's own zsh setup. Shared settings live in ~/.config/zsh/common.zsh; anything below overrides them. Installers may append here.
[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh

###### Program configurations ######

export DYLD_LIBRARY_PATH="$HOMEBREW_PREFIX/lib:$DYLD_LIBRARY_PATH" # ImageMagick / image.nvim installation step

# >>> conda initialize >>>
# !! Contents within this block are managed by 'conda init' !!
__conda_setup="$('/Users/ethankeshishian/miniconda3/bin/conda' 'shell.zsh' 'hook' 2> /dev/null)"
if [ $? -eq 0 ]; then
    eval "$__conda_setup"
else
    if [ -f "/Users/ethankeshishian/miniconda3/etc/profile.d/conda.sh" ]; then
        . "/Users/ethankeshishian/miniconda3/etc/profile.d/conda.sh"
    else
        export PATH="/Users/ethankeshishian/miniconda3/bin:$PATH"
    fi
fi
unset __conda_setup
# <<< conda initialize <<<

export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"  # This loads nvm
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"  # This loads nvm bash_completion

# Load Angular CLI autocompletion.
source <(ng completion script)

# The next line updates PATH for the Google Cloud SDK.
if [ -f '/Users/ethankeshishian/google-cloud-sdk/path.zsh.inc' ]; then . '/Users/ethankeshishian/google-cloud-sdk/path.zsh.inc'; fi

# The next line enables shell command completion for gcloud.
if [ -f '/Users/ethankeshishian/google-cloud-sdk/completion.zsh.inc' ]; then . '/Users/ethankeshishian/google-cloud-sdk/completion.zsh.inc'; fi

#####################


# Added by Antigravity CLI installer
export PATH="/Users/ethankeshishian/.local/bin:$PATH"
