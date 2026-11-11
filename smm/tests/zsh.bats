#!/usr/bin/env bats

load helpers

setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$REPO" SMM_HOST=Ethans-MacBook-Pro
  source "$REPO/smm/lib/common.sh"
  source "$REPO/smm/lib/setup.sh"
}

compare_original() {
  python3 - "$REPO" "$1" <<'PY'
from collections import Counter
from pathlib import Path
import sys

repo, host = Path(sys.argv[1]), sys.argv[2]
source = '[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh'
original = (repo / 'smm/tests/fixtures/zsh' / (host + '.zshrc')).read_text()
current = (repo / 'config/zsh' / (host + '.zshrc')).read_text()
common = (repo / 'config/zsh/common.zsh').read_text()
retired = (repo / 'config/zsh/retired-shared.zsh').read_text()
assert current.count(source) == 1
before, after = current.split(source)

def commands(text):
    lines = [' '.join(line.split()) for line in text.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    # The two EDITOR assignments have identical effect.
    return [line.replace("export EDITOR='nvim'", 'export EDITOR=nvim') for line in lines]

# Host-file lines deliberately rewritten or removed, mapped to their replacements.
rewritten = {}
if host.endswith('Mercury'):
    rewritten = {
        # fnm manages Node; nvm only slowed startup and ran a second compinit.
        'export NVM_DIR="$HOME/.nvm"': [],
        '[ -s "/opt/homebrew/opt/nvm/nvm.sh" ] && \\. "/opt/homebrew/opt/nvm/nvm.sh" # This loads nvm': [],
        '[ -s "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" ] && \\. "/opt/homebrew/opt/nvm/etc/bash_completion.d/nvm" # This loads nvm bash_completion': [],
        '[ -f "/Users/ethankeshishian/.ghcup/env" ] && . "/Users/ethankeshishian/.ghcup/env" # ghcup-env':
            ['[ -f "$HOME/.ghcup/env" ] && . "$HOME/.ghcup/env" # ghcup-env'],
        'export PATH="$PATH:/Users/ethankeshishian/.local/bin"': ['export PATH="$PATH:$HOME/.local/bin"'],
        'eval "$(direnv hook zsh)"': ['_cached_eval direnv direnv direnv hook zsh'],
    }

shared, gone, host_lines = set(commands(common)), set(commands(retired)), Counter(commands(before + after))
# Every original command is still shared, retired on purpose, rewritten on purpose, or kept in the host file.
expected_host = Counter()
for line in commands(original):
    if line in rewritten:
        expected_host.update(rewritten[line])
    elif line not in shared and line not in gone:
        expected_host[line] += 1
missing = expected_host - host_lines
assert not missing, f'host file lost: {missing}'
# Shared commands live only in common; structural fi/else/} may recur.
assert not (shared - {'fi', 'else', '}'}).intersection(host_lines)
# The shared file comes first so its instant prompt shows before host initialization runs.
assert not commands(before)
if host.endswith('Mercury'):
    assert 'NVM_DIR' not in current and 'Tailscale.app' in after
    assert 'fnm env' in after and 'direnv hook' in after
else:
    assert '__conda_setup=' in after and 'ng completion script' in after
    assert all(f'zinit snippet OMZP::{name}' in after for name in ('aws', 'kubectl', 'kubectx'))
PY
}

@test "Ethans-MacBook-Pro preserves original commands through the shared split" {
  compare_original Ethans-MacBook-Pro
}

@test "Mercury preserves original commands through the shared split" {
  compare_original Ethans-MacBook-Pro-Mercury
}

@test "shared zsh starts with instant prompt and uses shared history and doctor settings" {
  python3 - "$REPO/config/zsh/common.zsh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
lines = [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]
assert lines[0].startswith('if [[ -r "${XDG_CACHE_HOME:')
assert 'HISTSIZE=1000000' in lines
assert 'setopt share_history' in lines and 'setopt inc_append_history' not in lines
assert lines.index('export _ZO_DOCTOR=0') < lines.index('_cached_eval zoxide zoxide zoxide init --cmd cd zsh')
PY
}

@test "all zsh configs parse and repo CLI validates both links for each host" {
  local file
  for file in "$REPO"/config/zsh/* "$REPO/config/.p10k.zsh"; do
    run zsh -n "$file"
    [ "$status" -eq 0 ]
  done
  for SMM_HOST in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    export SMM_HOST
    run "$REPO/smm/bin/smm" validate zsh zsh-common
    [ "$status" -eq 0 ]
    [ "$output" = $'ok zsh\nok zsh-common' ]
  done
  [ ! -s "$TMP/calls.log" ]
}

@test "new host seeds header and source without shared commands or broken conditionals" {
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/config/zsh"
  cat > "$SMM_REPO/config/zsh/common.zsh" <<'ZSH'
export EDITOR='nvim'
alias nv=nvim
if [ -d "$HOME/plugins" ]; then
  source "$HOME/plugins/init.zsh"
fi
ZSH
  cat > "$HOME/.zshrc" <<'ZSH'
export EDITOR=nvim
alias   nv=nvim
if [ -d "$HOME/plugins" ]; then
  source "$HOME/plugins/init.zsh"
fi
if command -v fnm >/dev/null; then
  eval "$(fnm env --use-on-cd)"
fi
export EDITOR=vim
ZSH
  cp "$HOME/.zshrc" "$TMP/original"
  smm_seed_host_zsh New-Mac
  local file="$SMM_REPO/config/zsh/New-Mac.zshrc"
  [ "$(head -n 1 "$file")" = "# This Mac's own zsh setup. Shared settings live in ~/.config/zsh/common.zsh; anything below overrides them. Installers may append here." ]
  rg -Fx '[ -f ~/.config/zsh/common.zsh ] && source ~/.config/zsh/common.zsh' "$file"
  ! rg 'alias.*nv=|EDITOR=.*nvim|plugins' "$file"
  rg -Fx 'export EDITOR=vim' "$file"
  zsh -n "$file"
  cmp "$HOME/.zshrc" "$TMP/original"
  cp "$file" "$TMP/seeded"
  smm_seed_host_zsh New-Mac
  cmp "$file" "$TMP/seeded"
  rm "$HOME/.zshrc"
  smm_seed_host_zsh Fresh-Mac
  [ "$(wc -l < "$SMM_REPO/config/zsh/Fresh-Mac.zshrc" | tr -d ' ')" -eq 2 ]
}

@test "new host removes actual shared initialization blocks from either original host" {
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/config/zsh"
  cp "$REPO/config/zsh/common.zsh" "$REPO/config/zsh/retired-shared.zsh" "$SMM_REPO/config/zsh/"
  local host
  for host in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    cp "$REPO/smm/tests/fixtures/zsh/$host.zshrc" "$HOME/.zshrc"
    smm_seed_host_zsh "$host"
    zsh -n "$SMM_REPO/config/zsh/$host.zshrc"
    ! rg 'zinit|p10k|fzf --zsh|zoxide init|EDITOR|menu no|backward-kill-word' "$SMM_REPO/config/zsh/$host.zshrc"
  done
}
