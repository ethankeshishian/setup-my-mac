#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export REPO SMM_REPO="$HOME/Repos/setup-my-mac" SMM_BACKUP="$TMP/backup"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/config/nvim" "$SMM_REPO/result/sw/bin"
  echo '[{"name":"test","source":"config/test","target":".test","type":"file","validator":null,"reload":null}]' > "$SMM_REPO/manifest/links.json"
  echo '[]' > "$SMM_REPO/manifest/secrets.json"
  echo '[]' > "$SMM_REPO/manifest/nix-packages.json"
  echo '{"taps":[],"brews":[],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  echo original > "$SMM_REPO/config/test"
  cp "$SMM_REPO/config/test" "$HOME/.test"
  git -C "$SMM_REPO" add -A
  git -C "$SMM_REPO" commit -qm fixture
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  for tool in brew nvim aerospace sketchybar launchctl osascript open pgrep; do stub "$tool" 0; done
  stub scutil 0 Test-Mac
  stub darwin-rebuild 0 '42 date (current)'
  stub sudo 0
  sed_inplace 's/exit 0/exec "$@"/' "$TMP/bin/sudo"
  stub sysctl 0 '{ sec = 100, usec = 0 }'
}
@test "review 1 config preparation keeps originals through build failure" {
  SETUP_STEPS=(configs build)
  step_build_done() { return 1; }
  step_build_run() { [ -f "$HOME/.test" ] || return 99; return 1; }
  run cmd_setup
  [ "$status" -eq 1 ]
  [ "$(cat "$HOME/.test")" = original ]
  [ ! -L "$HOME/.test" ]
}
@test "review 1 failed first switch restores journaled originals and absent targets" {
  echo '[{"name":"test","source":"config/test","target":".test","type":"file","validator":null,"reload":null},{"name":"new","source":"config/test","target":".new","type":"file","validator":null,"reload":null}]' > "$SMM_REPO/manifest/links.json"
  SETUP_STEPS=(configs switch)
  smm_use_build_tools() { :; }; smm_run_validate() { :; }
  smm_switch() {
    [ ! -e "$HOME/.test" ] || return 99
    ln -s "$SMM_REPO/config/test" "$HOME/.test"
    ln -s "$SMM_REPO/config/test" "$HOME/.new"
    return 1
  }
  run cmd_setup
  [ "$status" -eq 1 ]
  [ ! -L "$HOME/.test" ]; [ "$(cat "$HOME/.test")" = original ]
  [ ! -e "$HOME/.new" ]; [ ! -L "$HOME/.new" ]
}
@test "review 2 invalid config with changed inputs never builds or switches" {
  validate_fixture() { echo rejected; return 1; }
  jq '.[0].validator="fixture"' "$SMM_REPO/manifest/links.json" > "$TMP/links"
  cp "$TMP/links" "$SMM_REPO/manifest/links.json"
  run cmd_apply
  [ "$status" -eq 1 ]; [ "$(cat "$HOME/.test")" = original ]
  ! calls | grep -Eq 'darwin-rebuild (build|switch)'
}
@test "review 3 apply interruption during switch rolls back without finalizing hash" {
  echo previous > "$SMM_STATE/applied.hash"
  stub darwin-rebuild 0 '42 date (current)'
  sed_inplace '/exit 0/i\
if [ "$1" = switch ] && [ "$2" = --flake ]; then kill -TERM "$PPID"; fi\
' "$TMP/bin/darwin-rebuild"
  run cmd_apply
  [ "$status" -eq 143 ]
  calls | grep -q 'switch --switch-generation 42'
  [ "$(cat "$SMM_STATE/applied.hash")" = previous ]
}
@test "review 3 health failure preserves previous applied hash" {
  echo previous > "$SMM_STATE/applied.hash"
  smm_health() { return 1; }; smm_health_reason() { echo not-running; }
  run cmd_apply
  [ "$status" -eq 1 ]
  [ "$(cat "$SMM_STATE/applied.hash")" = previous ]
}
@test "review 5 undo apply failure leaves upgrade eligible and clean" {
  echo old > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm baseline
  echo new > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm 'upgrade: fixture'
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  smm_run_apply() { return 1; }
  run cmd_undo
  [ "$status" -eq 1 ]; [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ "$(cat "$SMM_REPO/flake.lock")" = new ]
  [ -z "$(git -C "$SMM_REPO" status --porcelain)" ]
  smm_run_apply() { :; }
  run cmd_undo; [ "$status" -eq 0 ]
}
@test "review 6 setup streams step output before completion and preserves shell state" {
  SETUP_STEPS=(stream next)
  step_stream_done() { return 1; }; step_next_done() { return 1; }
  step_stream_run() {
    echo 'waiting for input'
    export SMM_HOST=Stream-Mac
    for i in $(seq 1 100); do
      grep -q 'waiting for input' "$TMP/live-output" && return 0
      sleep .01
    done
    return 1
  }
  step_next_run() { [ "$SMM_HOST" = Stream-Mac ]; }
  cmd_setup > "$TMP/live-output" 2>&1 &
  pid=$!
  wait "$pid"
  grep -q 'waiting for input' "$SMM_STATE/setup.log"
}
@test "review 7 absent aerospace server skips validation without swapping files" {
  stub pgrep 1
  echo live > "$HOME/.aerospace.toml"
  run validate_aerospace "$SMM_REPO/config/test"
  [ "$status" -eq 0 ]; [[ "$output" == *'skipped (aerospace not running)'* ]]
  [ "$(cat "$HOME/.aerospace.toml")" = live ]
  ! calls | grep -q '^aerospace '
}
@test "review 7 setup preview validates aerospace before dedupe and switch validates after activation" {
  smm_migrate_preview() { :; }; confirm() { :; }
  smm_run_validate() { echo "validate $*" >> "$TMP/order"; }
  smm_use_build_tools() { :; }; smm_switch() { echo switch >> "$TMP/order"; }
  step_preview_run
  step_switch_run
  [ "$(head -n 1 "$TMP/order")" = "validate $SMM_REPO aerospace" ]
  [ "$(tail -n 1 "$TMP/order")" = "validate $SMM_REPO aerospace" ]
  [ "$(sed -n '$p' "$TMP/order")" != switch ]
}
@test "review 8 initial activation succeeds without a previous generation" {
  stub darwin-rebuild 0 ''
  stub nix 0
  smm_health() { :; }
  run cmd_apply
  [ "$status" -eq 0 ]
  calls | grep -q "switch --flake $SMM_REPO#Test-Mac"
  [ -s "$SMM_STATE/applied.hash" ]
}
@test "review 8 initial setup failure restores originals and deduped brew" {
  stub darwin-rebuild 0 ''
  echo 'brew sketchybar' > "$SMM_STATE/deduped"
  SETUP_STEPS=(configs switch health)
  smm_use_build_tools() { :; }; smm_run_validate() { :; }
  smm_switch() { ln -s "$SMM_REPO/config/test" "$HOME/.test"; }
  step_health_done() { return 1; }; smm_health() { return 1; }
  run cmd_setup
  [ "$status" -eq 1 ]; [ "$(cat "$HOME/.test")" = original ]; [ ! -L "$HOME/.test" ]
  calls | grep -qx 'brew install sketchybar'
  ! calls | grep -q switch-generation
}
@test "review 9 missing rebuild uses flake bootstrap for build and switch" {
  command() {
    if [ "${1:-}" = -v ] && [ "${2:-}" = darwin-rebuild ]; then return 1; fi
    builtin command "$@"
  }
  stub nix 0
  smm_build
  smm_switch
  calls | grep -qx "nix --extra-experimental-features nix-command flakes run $SMM_REPO#darwin-rebuild -- build --flake $SMM_REPO#Test-Mac"
  calls | grep -qx "nix --extra-experimental-features nix-command flakes run $SMM_REPO#darwin-rebuild -- switch --flake $SMM_REPO#Test-Mac"
}
@test "review 10 absent brew is empty inventory for preview and adoption" {
  command() {
    if [ "${1:-}" = -v ] && [ "${2:-}" = brew ]; then return 1; fi
    builtin command "$@"
  }
  stub brew 127
  run smm_brew_undeclared; [ "$status" -eq 0 ]; [ -z "$output" ]
  run smm_brew_duplicates; [ "$status" -eq 0 ]; [ -z "$output" ]
  run step_brew_adopt_run; [ "$status" -eq 0 ]
  ! calls | grep -q '^brew '
}
@test "review 12 indirect home-manager links count as linked in status" {
  rm "$HOME/.test"
  ln -s "$SMM_REPO/config/test" "$TMP/store-link"
  ln -s "$TMP/store-link" "$HOME/.test"
  stub gh 0
  run cmd_status
  [ "$status" -eq 0 ]; [ "$output" = clean ]
}
@test "review 13 apply restores changed plugin pins before validation and tracks success" {
  echo '{}' > "$SMM_REPO/config/nvim/lazy-lock.json"
  smm_nix_inputs_hash > "$SMM_STATE/applied.hash"
  smm_nvim_run() { echo restore >> "$TMP/order"; }
  smm_validate() { echo validate >> "$TMP/order"; }
  cmd_apply
  [ "$(head -n 1 "$TMP/order")" = restore ]
  [ -s "$SMM_STATE/lazy-lock.hash" ]
  : > "$TMP/order"
  cmd_apply
  ! grep -q restore "$TMP/order"
}
@test "review 13 failed plugin restore restores previous pins and plugins preserving edit" {
  echo '{"p":{"commit":"old"}}' > "$SMM_REPO/config/nvim/lazy-lock.json"
  smm_nix_inputs_hash > "$SMM_STATE/applied.hash"
  smm_nvim_run() { cat "$SMM_REPO/config/nvim/lazy-lock.json" > "$TMP/plugins"; }
  cmd_apply
  echo '{"p":{"commit":"new"}}' > "$SMM_REPO/config/nvim/lazy-lock.json"
  smm_nvim_run() {
    cat "$SMM_REPO/config/nvim/lazy-lock.json" > "$TMP/plugins"
    ! grep -q new "$TMP/plugins"
  }
  run cmd_apply
  [ "$status" -eq 1 ]
  grep -q old "$TMP/plugins"
  grep -q new "$SMM_REPO/config/nvim/lazy-lock.json"
}
@test "review 15 restart request expires after a subsequent boot" {
  smm_need_restart defaults
  stub sysctl 0 '{ sec = 200, usec = 0 }'
  confirm() { echo prompted >> "$TMP/calls.log"; return 0; }
  run step_finish_run; [ "$status" -eq 0 ]
  ! calls | grep -q prompted
  [ ! -s "$SMM_STATE/restart-needed" ]
}
@test "review 6 confirm reads controlling tty even when stdin is redirected" {
  run run_tty /bin/bash -c 'source "$REPO/smm/lib/common.sh"; confirm "TTY prompt"'
  [ "$status" -eq 0 ]
}
@test "review 11 piped bootstrap attaches setup stdin to controlling tty" {
  stub uname 0 arm64
  stub nix 0
  sed_inplace '/exit 0/i\
[ -t 0 ] || exit 91\
' "$TMP/bin/nix"
  run run_tty /bin/bash "$REPO/bootstrap.sh"
  [ "$status" -eq 0 ]
  calls | grep -q '#smm -- setup'
}
@test "review 1 setup TERM after activation restores originals and previous hash" {
  echo previous > "$SMM_STATE/applied.hash"
  local started=$SECONDS
  run /bin/bash -c '
    for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
    SETUP_STEPS=(configs switch permissions)
    smm_use_build_tools() { :; }; smm_run_validate() { :; }
    smm_switch() { ln -s "$SMM_REPO/config/test" "$HOME/.test"; }
    step_permissions_done() { return 1; }
    step_permissions_run() { bash -c "kill -TERM \$PPID"; }
    cmd_setup
  '
  [ "$((SECONDS - started))" -lt 3 ]
  [ "$status" -eq 143 ]
  [ "$(cat "$HOME/.test")" = original ]; [ ! -L "$HOME/.test" ]
  [ "$(cat "$SMM_STATE/applied.hash")" = previous ]
  calls | grep -q 'switch --switch-generation 42'
}
@test "review 1 setup INT after activation restores originals and previous hash" {
  echo previous > "$SMM_STATE/applied.hash"
  local started=$SECONDS
  run /bin/bash -c '
    for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
    SETUP_STEPS=(configs switch permissions)
    smm_use_build_tools() { :; }; smm_run_validate() { :; }
    smm_switch() { ln -s "$SMM_REPO/config/test" "$HOME/.test"; }
    step_permissions_done() { return 1; }
    step_permissions_run() { bash -c "kill -INT \$PPID"; }
    cmd_setup
  '
  [ "$((SECONDS - started))" -lt 3 ]
  [ "$status" -eq 130 ]
  [ "$(cat "$HOME/.test")" = original ]; [ ! -L "$HOME/.test" ]
  [ "$(cat "$SMM_STATE/applied.hash")" = previous ]
  calls | grep -q 'switch --switch-generation 42'
}
@test "review 5 undo plugin failure rolls back activation without a revert commit" {
  echo old > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm baseline
  echo new > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm 'upgrade: fixture'
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  smm_run_apply() { :; }; smm_nvim_run() { return 1; }
  run cmd_undo
  [ "$status" -eq 1 ]; [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ "$(cat "$SMM_REPO/flake.lock")" = new ]
  calls | grep -q 'switch --switch-generation 42'
}
@test "review 3 apply INT during health restores previous state and plugins" {
  echo previous > "$SMM_STATE/applied.hash"
  smm_health() { bash -c 'kill -INT "$PPID"'; }
  run cmd_apply
  [ "$status" -eq 130 ]
  [ "$(cat "$SMM_STATE/applied.hash")" = previous ]
  calls | grep -q 'switch --switch-generation 42'
}
@test "review 1 initial activation journals missing targets even when configs step is already done" {
  rm "$HOME/.test"
  stub darwin-rebuild 0 ''
  SETUP_STEPS=(configs switch health)
  smm_use_build_tools() { :; }; smm_run_validate() { :; }
  smm_switch() { ln -s "$SMM_REPO/config/test" "$HOME/.test"; }
  step_health_done() { return 1; }; smm_health() { return 1; }
  run cmd_setup
  [ "$status" -eq 1 ]; [ ! -e "$HOME/.test" ]; [ ! -L "$HOME/.test" ]
}
@test "review 8 initial generation bootstraps rebuild even when executable is on PATH" {
  stub darwin-rebuild 0 ''
  stub nix 0
  smm_build
  smm_switch
  calls | grep -qx "nix --extra-experimental-features nix-command flakes run $SMM_REPO#darwin-rebuild -- build --flake $SMM_REPO#Test-Mac"
  calls | grep -qx "nix --extra-experimental-features nix-command flakes run $SMM_REPO#darwin-rebuild -- switch --flake $SMM_REPO#Test-Mac"
}
