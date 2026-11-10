#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/modules" "$SMM_REPO/hosts" "$SMM_REPO/smm/lib"
  printf 'flake\n' > "$SMM_REPO/flake.nix"
  printf '{}\n' > "$SMM_REPO/manifest/homebrew.json"
  source "$REPO/smm/lib/common.sh"
  source "$REPO/smm/lib/build.sh"
  stub scutil 0 Test-Mac
  stub darwin-rebuild 0
  stub sudo 0
  sed -i '' 's/exit 0/exec "$@"/' "$TMP/bin/sudo"
}
@test "unchanged inputs returns 1" {
  smm_nix_inputs_hash > "$SMM_STATE/applied.hash"
  run smm_nix_changed
  [ "$status" -eq 1 ]
}
@test "editing manifest changes hash but linked configs do not" {
  smm_nix_inputs_hash > "$SMM_STATE/applied.hash"
  mkdir "$SMM_REPO/config"
  printf edit > "$SMM_REPO/config/test"
  ! smm_nix_changed
  printf '{"changed":true}\n' > "$SMM_REPO/manifest/homebrew.json"
  smm_nix_changed
}
@test "generation parsed from list" {
  stub darwin-rebuild 0 $'  41 date\n  42 date (current)'
  [ "$(smm_generation)" = 42 ]
}
@test "rollback calls switch-generation N and clears hash" {
  printf old > "$SMM_STATE/applied.hash"
  smm_rollback 42
  calls | grep -qx 'darwin-rebuild switch --switch-generation 42'
  [ ! -e "$SMM_STATE/applied.hash" ]
}
@test "build failure leaves applied hash untouched" {
  printf old > "$SMM_STATE/applied.hash"
  stub darwin-rebuild 1
  run smm_build
  [ "$status" -ne 0 ]
  [ "$(cat "$SMM_STATE/applied.hash")" = old ]
  [ ! -e "$SMM_STATE/last-build" ]
}
@test "build records output path and switch stores hash only on success" {
  mkdir "$SMM_REPO/built-system"
  ln -s built-system "$SMM_REPO/result"
  smm_build
  [ "$(cat "$SMM_STATE/last-build")" = "$(cd -P "$SMM_REPO/built-system" && pwd)" ]
  calls | grep -qx "darwin-rebuild build --flake $SMM_REPO#Test-Mac"
  smm_switch
  [ "$(cat "$SMM_STATE/applied.hash")" = "$(smm_nix_inputs_hash)" ]
  printf old > "$SMM_STATE/applied.hash"
  stub darwin-rebuild 1
  run smm_switch
  [ "$status" -ne 0 ]
  [ "$(cat "$SMM_STATE/applied.hash")" = old ]
}
@test "missing current generation fails" {
  stub darwin-rebuild 0 '41 date'
  run smm_generation
  [ "$status" -ne 0 ]
}
