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
  source "$REPO/smm/lib/transaction.sh"
  stub scutil 0 Test-Mac
  stub darwin-rebuild 0 '42 date (current)'
  stub sudo 0
  sed_inplace 's/exit 0/exec "$@"/' "$TMP/bin/sudo"
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
  stub darwin-rebuild 0 '42 date (current)'
  sed_inplace '/exit 0/i\
[ "$1" != build ] || exit 1\
' "$TMP/bin/darwin-rebuild"
  run smm_build
  [ "$status" -ne 0 ]
  [ "$(cat "$SMM_STATE/applied.hash")" = old ]
  [ ! -e "$SMM_STATE/last-build" ]
}
@test "build records output path and hash finalizes separately after switch" {
  mkdir "$SMM_REPO/built-system"
  ln -s built-system "$SMM_REPO/result"
  smm_build
  [ "$(cat "$SMM_STATE/last-build")" = "$(cd -P "$SMM_REPO/built-system" && pwd)" ]
  calls | grep -qx "darwin-rebuild build --flake $SMM_REPO#Test-Mac"
  smm_switch
  [ ! -f "$SMM_STATE/applied.hash" ]
  smm_finalize_apply
  [ "$(cat "$SMM_STATE/applied.hash")" = "$(smm_nix_inputs_hash)" ]
  printf old > "$SMM_STATE/applied.hash"
  stub darwin-rebuild 0 '42 date (current)'
  sed_inplace '/exit 0/i\
[ "$1" != switch ] || exit 1\
' "$TMP/bin/darwin-rebuild"
  run smm_switch
  [ "$status" -ne 0 ]
  [ "$(cat "$SMM_STATE/applied.hash")" = old ]
}
@test "generation comes from the system profile link without listing generations" {
  mkdir -p "$TMP/profiles"
  ln -s /nix/store/x-darwin-system "$TMP/profiles/system-7-link"
  ln -s system-7-link "$TMP/profiles/system"
  stub darwin-rebuild 1 'error: opening lock file: Permission denied'
  [ "$(smm_generation)" = 7 ]
  ! calls | grep -q 'darwin-rebuild --list-generations' || return 1
}
@test "missing current generation means initial activation" {
  stub darwin-rebuild 0 '41 date'
  run smm_generation
  [ "$status" -eq 0 ]; [ -z "$output" ]
}

@test "flake snapshots reuse unchanged content and invalidate for file content mode and deletion" {
  make_repo "$SMM_REPO"
  export SMM_AGENT_SETUP=1
  first=$(smm_flake_ref)
  [ "$first" = "$(smm_flake_ref)" ]
  echo edit > "$SMM_REPO/flake.nix"
  second=$(smm_flake_ref)
  [ "$second" != "$first" ]
  chmod +x "$SMM_REPO/flake.nix"
  third=$(smm_flake_ref)
  [ "$third" != "$second" ]
  rm "$SMM_REPO/flake.nix"
  fourth=$(smm_flake_ref)
  [ "$fourth" != "$third" ]
  echo private > "$SMM_REPO/secret.env"
  echo secret.env > "$SMM_REPO/.gitignore"
  fifth=$(smm_flake_ref)
  echo changed-private > "$SMM_REPO/secret.env"
  [ "$fifth" = "$(smm_flake_ref)" ]
}
@test "successful switch prunes old snapshots but keeps last build and failure preserves snapshots" {
  make_repo "$SMM_REPO"
  export SMM_AGENT_SETUP=1
  first=$(smm_flake_ref)
  echo new > "$SMM_REPO/flake.nix"
  second=$(smm_flake_ref)
  printf '%s\n' "$second" > "$SMM_STATE/last-build-flake"
  stub sudo 1
  run smm_switch
  [ "$status" -ne 0 ]
  [ -d "${first#path:}" ]
  stub sudo 0
  run smm_switch
  [ "$status" -eq 0 ]
  [ ! -d "${first#path:}" ]
  [ -d "${second#path:}" ]
  [ "$(find "$SMM_STATE" -maxdepth 1 -type d -name 'flake.*' | wc -l | tr -d ' ')" = 1 ]
}
