#!/usr/bin/env bash

setup_tmp() {
  TMP=$(mktemp -d "${BATS_TEST_TMPDIR:-${TMPDIR:-/tmp}}/smm.XXXXXX")
  export TMP
  export HOME="$TMP/home"
  export SMM_STATE="$TMP/state"
  export XDG_CONFIG_HOME="$HOME/.config"
  export XDG_DATA_HOME="$HOME/.local/share"
  export XDG_CACHE_HOME="$HOME/.cache"
  export GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_SYSTEM=/dev/null GIT_CONFIG_NOSYSTEM=1
  unset GIT_DIR GIT_WORK_TREE GIT_INDEX_FILE
  mkdir -p "$HOME" "$SMM_STATE" "$TMP/bin"
  export PATH="$TMP/bin:$PATH"
  : > "$TMP/calls.log"
  local tool
  for tool in aerospace sketchybar brew darwin-rebuild sudo op gh launchctl osascript scutil systemextensionsctl karabiner_cli ghostty nvim open defaults killall kitten curl; do
    stub "$tool" 127
  done
}

stub() {
  local name=$1 exit_code=${2:-0} stdout=${3:-}
  case "$name" in
    ''|*[!a-zA-Z0-9_.-]*) return 2 ;;
  esac
  case "$exit_code" in
    ''|*[!0-9]*) return 2 ;;
  esac
  {
    printf '#!/usr/bin/env bash\n'
    printf 'stub_name=%q\nstub_stdout=%q\n' "$name" "$stdout"
    cat <<'STUB'
printf '%s %s\n' "$stub_name" "$*" >> "$TMP/calls.log"
if [ -n "$stub_stdout" ]; then printf '%s\n' "$stub_stdout"; fi
STUB
    printf 'exit %s\n' "$exit_code"
  } > "$TMP/bin/$name"
  chmod +x "$TMP/bin/$name"
}

calls() {
  cat "$TMP/calls.log"
}

make_repo() {
  git init --quiet --initial-branch=smm-test "$1"
  git -C "$1" config --local user.name 'Smm Test'
  git -C "$1" config --local user.email smm-test@example.invalid
  git -C "$1" -c commit.gpgsign=false commit --quiet --allow-empty -m 'Initial test commit'
}

make_remote_pair() {
  make_repo "$TMP/seed"
  git clone --quiet --bare "$TMP/seed" "$TMP/remote.git"
  local clone
  for clone in a b; do
    git clone --quiet "$TMP/remote.git" "$TMP/$clone"
    git -C "$TMP/$clone" config --local user.name 'Smm Test'
    git -C "$TMP/$clone" config --local user.email smm-test@example.invalid
  done
}
