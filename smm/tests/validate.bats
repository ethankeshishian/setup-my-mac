#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/config/ghostty" "$SMM_REPO/config/sketchybar"
  cat > "$SMM_REPO/manifest/links.json" <<'JSON'
[{"name":"aerospace","source":"config/aero","validator":"aerospace"},
 {"name":"ghostty","source":"config/ghostty","validator":"ghostty"},
 {"name":"kitty","source":"config/kitty","validator":null}]
JSON
  printf 'new\n' > "$SMM_REPO/config/aero"
  stub aerospace 0
  stub ghostty 0
}
load_lib() {
  source "$REPO/smm/lib/common.sh"
  source "$REPO/smm/lib/validate.sh"
  source "$REPO/smm/lib/prefs.sh"
}
@test "reports fail with first error line" {
  stub ghostty 1 $'bad key\nsecond error'
  run "$REPO/smm/bin/smm" validate ghostty
  [ "$status" -eq 1 ]
  [ "$output" = 'fail ghostty: bad key' ]
}
@test "all ok returns 0 and exports failed links" {
  load_lib
  smm_validate "$SMM_REPO"
  [ -z "$SMM_FAILED_LINKS" ]
  stub ghostty 1 'bad key'
  smm_validate "$SMM_REPO" && return 1
  [ "$SMM_FAILED_LINKS" = ghostty ]
}
@test "aerospace swap restores original file" {
  load_lib
  printf 'original\n' > "$HOME/.aerospace.toml"
  stub aerospace 1
  run validate_aerospace "$SMM_REPO/config/aero"
  [ "$status" -eq 1 ]
  [ ! -L "$HOME/.aerospace.toml" ]
  [ "$(cat "$HOME/.aerospace.toml")" = original ]
  [ ! -e "$SMM_STATE/aerospace.swap" ]
}
@test "aerospace swap restores on SIGINT" {
  load_lib
  printf 'original\n' > "$HOME/.aerospace.toml"
  stub aerospace 0
  # Keep the PATH stub alive until the validator is interrupted.
  sed -i '' 's/exit 0/echo "$PPID" > "$TMP\/validator.pid"; sleep 20/' "$TMP/bin/aerospace"
  export REPO
  python3 - <<'PY'
import os, signal, subprocess, time
p = subprocess.Popen(['/bin/bash', '-c', 'source "$REPO/smm/lib/common.sh"; source "$REPO/smm/lib/validate.sh"; validate_aerospace "$SMM_REPO/config/aero"'])
try:
    for _ in range(200):
        if os.path.exists(os.path.join(os.environ['TMP'], 'validator.pid')):
            break
        time.sleep(.01)
    else:
        raise AssertionError('validator did not swap')
    # Signal the subshell which owns the swap and traps.
    with open(os.path.join(os.environ['TMP'], 'validator.pid')) as f:
        validator_pid = int(f.read())
    os.kill(validator_pid, signal.SIGINT)
    assert p.wait(timeout=5) == 130
finally:
    if p.poll() is None:
        p.kill()
PY
  [ ! -L "$HOME/.aerospace.toml" ]
  [ "$(cat "$HOME/.aerospace.toml")" = original ]
  [ ! -e "$SMM_STATE/aerospace.swap" ]
}
@test "null validator skipped" {
  run "$REPO/smm/bin/smm" validate kitty
  [ "$status" -eq 0 ]
  [ -z "$output" ]
  [ -z "$(calls)" ]
}
@test "named subset only" {
  run "$REPO/smm/bin/smm" validate ghostty
  [ "$status" -eq 0 ]
  [ "$output" = 'ok ghostty' ]
  ! calls | grep -q aerospace
}
@test "aerospace preserves original symlink and absent target" {
  load_lib
  ln -s "$TMP/missing" "$HOME/.aerospace.toml"
  validate_aerospace "$SMM_REPO/config/aero"
  [ "$(readlink "$HOME/.aerospace.toml")" = "$TMP/missing" ]
  rm "$HOME/.aerospace.toml"
  validate_aerospace "$SMM_REPO/config/aero"
  [ ! -L "$HOME/.aerospace.toml" ]
}
@test "karabiner lints each profile separately" {
  load_lib
  mkdir "$TMP/karabiner"
  printf '%s\n' '{"profiles":[{"complex_modifications":{"rules":[{"description":"one"}]}},{"complex_modifications":{"rules":[]}}]}' > "$TMP/karabiner/karabiner.json"
  stub karabiner_cli 0
  validate_karabiner "$TMP/karabiner"
  [ "$(calls | grep -c lint-complex-modifications)" -eq 2 ]
}
@test "sketchybar checks nested scripts and nvim rejects stderr errors" {
  load_lib
  mkdir -p "$TMP/bar/nested"
  printf 'true\n' > "$TMP/bar/sketchybarrc"
  printf 'if\n' > "$TMP/bar/nested/bad.sh"
  run validate_sketchybar "$TMP/bar"
  [ "$status" -ne 0 ]
  stub nvim 0
  printf 'printf "Error: startup failed\\n" >&2\n' >> "$TMP/bin/nvim"
  sed -i '' '/^exit 0$/d' "$TMP/bin/nvim"
  run validate_nvim "$TMP/bar"
  [ "$status" -ne 0 ]
}
@test "existing live aerospace link needs no swap" {
  load_lib
  ln -s "$SMM_REPO/config/aero" "$HOME/.aerospace.toml"
  validate_aerospace "$SMM_REPO/config/aero"
  [ "$(readlink "$HOME/.aerospace.toml")" = "$SMM_REPO/config/aero" ]
  [ ! -e "$SMM_STATE/aerospace.swap" ]
  [ ! -e "$SMM_STATE/aerospace.lock" ]
}
@test "tmux zsh plist and ghostty use the specified validator arguments" {
  load_lib
  stub tmux 0
  stub zsh 0
  stub plutil 0
  validate_tmux "$TMP/tmux file"
  validate_zsh "$TMP/zsh file"
  validate_plist "$TMP/plist file"
  validate_ghostty "$TMP/ghostty dir"
  calls | grep -Fxq "tmux -L smm-validate -f /dev/null start-server ; source-file -n $TMP/tmux file ; kill-server"
  calls | grep -Fxq "zsh -n $TMP/zsh file"
  calls | grep -Fxq "plutil -lint $TMP/plist file"
  calls | grep -Fxq "ghostty +validate-config --config-file=$TMP/ghostty dir/config"
}
@test "aerospace restores when interrupted immediately after moving original" {
  load_lib
  printf original > "$HOME/.aerospace.toml"
  stub mv 0
  sed -i '' '/^exit 0$/d' "$TMP/bin/mv"
  cat >> "$TMP/bin/mv" <<'STUB'
/bin/mv "$@" || exit 1
if [ ! -e "$TMP/mv-interrupted" ]; then
  touch "$TMP/mv-interrupted"
  kill -INT "$PPID"
fi
STUB
  run validate_aerospace "$SMM_REPO/config/aero"
  [ "$status" -eq 130 ]
  [ "$(cat "$HOME/.aerospace.toml")" = original ]
  [ ! -e "$SMM_STATE/aerospace.swap" ]
}

@test "nvim validation seeds isolated XDG dirs and cleans them after success or failure" {
  load_lib
  export XDG_STATE_HOME="$HOME/.local/state"
  mkdir -p "$XDG_DATA_HOME/nvim/lazy" "$XDG_CACHE_HOME/nvim" "$XDG_STATE_HOME/nvim"
  printf plugin > "$XDG_DATA_HOME/nvim/lazy/installed"
  printf cache > "$XDG_CACHE_HOME/nvim/cached"
  printf state > "$XDG_STATE_HOME/nvim/session"
  stub nvim 0
  sed -i '' '/^exit 0$/d' "$TMP/bin/nvim"
  cat >> "$TMP/bin/nvim" <<'STUB'
[ "$(cat "$XDG_DATA_HOME/nvim/lazy/installed")" = plugin ] || exit 91
[ "$(cat "$XDG_CACHE_HOME/nvim/cached")" = cache ] || exit 92
[ ! -e "$XDG_STATE_HOME/nvim/session" ] || exit 93
printf '%s\n' "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$XDG_CACHE_HOME" "$XDG_STATE_HOME" > "$TMP/nvim-xdg"
printf changed > "$XDG_DATA_HOME/nvim/lazy/installed"
printf changed > "$XDG_CACHE_HOME/nvim/cached"
mkdir -p "$XDG_STATE_HOME/nvim"
printf changed > "$XDG_STATE_HOME/nvim/session"
exit "${SMM_TEST_NVIM_STATUS:-0}"
STUB
  local expected path
  for expected in 0 17; do
    export SMM_TEST_NVIM_STATUS=$expected
    run validate_nvim "$SMM_REPO/config/ghostty"
    [ "$status" -eq "$expected" ]
    [ "$(cat "$XDG_DATA_HOME/nvim/lazy/installed")" = plugin ]
    [ "$(cat "$XDG_CACHE_HOME/nvim/cached")" = cache ]
    [ "$(cat "$XDG_STATE_HOME/nvim/session")" = state ]
    while IFS= read -r path; do
      [ ! -e "$path" ]
    done < "$TMP/nvim-xdg"
  done
}

@test "nvim validation falls back to regular copies when APFS clones fail" {
  load_lib
  mkdir -p "$XDG_DATA_HOME/nvim" "$XDG_CACHE_HOME/nvim"
  printf plugin > "$XDG_DATA_HOME/nvim/installed"
  printf cache > "$XDG_CACHE_HOME/nvim/cached"
  stub cp 0
  sed -i '' '/^exit 0$/d' "$TMP/bin/cp"
  cat >> "$TMP/bin/cp" <<'STUB'
[ "$1" != -cR ] || exit 1
exec /bin/cp "$@"
STUB
  stub nvim 0
  sed -i '' '/^exit 0$/d' "$TMP/bin/nvim"
  cat >> "$TMP/bin/nvim" <<'STUB'
[ "$(cat "$XDG_DATA_HOME/nvim/installed")" = plugin ] || exit 91
[ "$(cat "$XDG_CACHE_HOME/nvim/cached")" = cache ] || exit 92
STUB
  run validate_nvim "$SMM_REPO/config/ghostty"
  [ "$status" -eq 0 ]
  [ "$(calls | grep -c 'cp -cR')" -eq 2 ]
  [ "$(calls | grep -c 'cp -R')" -eq 2 ]
}
