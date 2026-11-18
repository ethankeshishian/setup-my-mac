#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  make_repo "$SMM_REPO"
  printf 'zero\n' > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm baseline
  for lib in "$REPO"/smm/lib/*.sh; do source "$lib"; done
  [ ! -f "$REPO/smm/cmd/upgrade.sh" ] || source "$REPO/smm/cmd/upgrade.sh"
  [ ! -f "$REPO/smm/cmd/undo.sh" ] || source "$REPO/smm/cmd/undo.sh"
  stub nvim 0
  smm_run_apply() { echo apply >> "$TMP/calls.log"; }
}
upgrade_fixture() {
  printf '%s\n' "$1" > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm "upgrade: test" -m 'casks: example'
}
@test "reverts latest upgrade commit and restores plugins" {
  upgrade_fixture one
  run cmd_undo
  [ "$status" -eq 0 ]; [ "$(cat "$SMM_REPO/flake.lock")" = zero ]
  calls | grep -qx apply; calls | grep -Fq '+Lazy! restore'
  [[ "$output" == *"Homebrew app versions can't be reverted"* ]]
}
@test "second undo reverts previous upgrade even with identical subjects" {
  upgrade_fixture one; upgrade_fixture one-again
  run cmd_undo; [ "$status" -eq 0 ]
  run cmd_undo; [ "$status" -eq 0 ]
  [ "$(cat "$SMM_REPO/flake.lock")" = zero ]
}
@test "no upgrade reports message" {
  run cmd_undo; [ "$status" -eq 1 ]; [[ "$output" == *'no upgrade to undo'* ]]
}
@test "dirty tree refuses" {
  upgrade_fixture one; touch "$SMM_REPO/dirty"
  run cmd_undo; [ "$status" -eq 1 ]; [[ "$output" == *'commit or sync first'* ]]
}
@test "conflicting revert aborts cleanly" {
  upgrade_fixture one
  printf 'later\n' > "$SMM_REPO/flake.lock"
  git -C "$SMM_REPO" add -A; git -C "$SMM_REPO" commit -qm later
  before=$(git -C "$SMM_REPO" rev-parse HEAD)
  run cmd_undo; [ "$status" -eq 1 ]
  [[ "$output" == *'later changes touch the same lock files; undo by hand'* ]]
  [ "$(git -C "$SMM_REPO" rev-parse HEAD)" = "$before" ]
  [ -z "$(git -C "$SMM_REPO" status --porcelain)" ]
  [ ! -f "$SMM_REPO/.git/REVERT_HEAD" ]
}
@test "cask-only upgrade can be marked undone once" {
  git -C "$SMM_REPO" commit --allow-empty -qm 'upgrade: 0 inputs, 0 plugins' -m 'casks: example'
  run cmd_undo; [ "$status" -eq 0 ]
  [[ "$output" == *"Homebrew app versions can't be reverted"* ]]
  run cmd_undo; [ "$status" -eq 1 ]; [[ "$output" == *'no upgrade to undo'* ]]
}
@test "plugin restore first moves lazy.nvim to its locked commit" {
  lazy="$TMP/data/nvim/lazy/lazy.nvim"
  mkdir -p "$lazy" "$SMM_REPO/config/nvim"
  git -C "$lazy" init -q
  git -C "$lazy" -c user.name=t -c user.email=t@t commit -q --allow-empty -m old
  old=$(git -C "$lazy" rev-parse HEAD)
  git -C "$lazy" -c user.name=t -c user.email=t@t commit -q --allow-empty -m new
  new=$(git -C "$lazy" rev-parse HEAD)
  git -C "$lazy" checkout -q "$old"
  printf '{"lazy.nvim":{"branch":"main","commit":"%s"}}\n' "$new" > "$SMM_REPO/config/nvim/lazy-lock.json"
  XDG_DATA_HOME="$TMP/data" smm_nvim_run '+Lazy! restore'
  [ "$(git -C "$lazy" rev-parse HEAD)" = "$new" ]
  calls | grep -q '^nvim --headless +Lazy! restore +qa$'
}
