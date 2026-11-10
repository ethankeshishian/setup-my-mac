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
assert current.count(source) == 1
before, after = current.split(source)

def commands(text):
    lines = [' '.join(line.split()) for line in text.splitlines()
             if line.strip() and not line.lstrip().startswith('#')]
    # The two EDITOR assignments have identical effect.
    return [line.replace("export EDITOR='nvim'", 'export EDITOR=nvim') for line in lines]

expected = Counter(commands(original))
if host == 'Ethans-MacBook-Pro':
    del expected['HISTSIZE=5000']
    expected['HISTSIZE=1000000'] = 1
    expected['setopt inc_append_history'] = 1
expected['export _ZO_DOCTOR=0'] = 1
# thefuck was removed from nixpkgs; pay-respects keeps the same alias
del expected['eval $(thefuck --alias)']
expected['eval "$(pay-respects zsh --alias fuck)"'] = 1
actual = Counter(commands(before + common + after))
assert actual == expected, f'missing: {expected-actual}\nextra: {actual-expected}'
# Every shared command occurs only in common; structural fi/else may recur.
shared = set(commands(common)) - {'fi', 'else'}
assert not shared.intersection(commands(before + after))
if host.endswith('Mercury'):
    assert 'export NVM_DIR=' in before and 'Tailscale.app' in before
    assert 'fnm env' in after and 'direnv hook' in after
else:
    assert not commands(before)
    assert '__conda_setup=' in after and 'ng completion script' in after
PY
}

@test "Ethans-MacBook-Pro preserves original commands through the shared split" {
  compare_original Ethans-MacBook-Pro
}

@test "Mercury preserves original commands through the shared split" {
  compare_original Ethans-MacBook-Pro-Mercury
}

@test "shared zsh starts with instant prompt and uses Mercury history and doctor settings" {
  python3 - "$REPO/config/zsh/common.zsh" <<'PY'
from pathlib import Path
import sys
text = Path(sys.argv[1]).read_text()
lines = [line.strip() for line in text.splitlines() if line.strip() and not line.lstrip().startswith('#')]
assert lines[0].startswith('if [[ -r "${XDG_CACHE_HOME:')
assert 'HISTSIZE=1000000' in lines
assert 'setopt inc_append_history' in lines
assert lines.index('export _ZO_DOCTOR=0') < lines.index('eval "$(zoxide init --cmd cd zsh)"')
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
  cp "$REPO/config/zsh/common.zsh" "$SMM_REPO/config/zsh/common.zsh"
  local host
  for host in Ethans-MacBook-Pro Ethans-MacBook-Pro-Mercury; do
    cp "$REPO/smm/tests/fixtures/zsh/$host.zshrc" "$HOME/.zshrc"
    smm_seed_host_zsh "$host"
    zsh -n "$SMM_REPO/config/zsh/$host.zshrc"
    ! rg 'zinit|p10k|fzf --zsh|zoxide init|EDITOR' "$SMM_REPO/config/zsh/$host.zshrc"
  done
}
