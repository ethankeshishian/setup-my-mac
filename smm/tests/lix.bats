#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_NIX_ROOT="$TMP/nix"
  mkdir -p "$SMM_NIX_ROOT"
  for file in "$REPO"/smm/lib/*.sh; do source "$file"; done
  stub nix 0 'nix (Lix, like Nix) 2.95.2'
  stub nix-env 0 legacy-package
  stub nix-installer 0
  cp "$TMP/bin/nix-installer" "$SMM_NIX_ROOT/nix-installer"
  choose() { echo 'keep Lix'; }
}
@test "smm_nix adds feature flags and preserves argument boundaries" {
  stub nix 0
  sed -i '' '/exit 0/i\
[ "$#" -eq 5 ] && [ "$2" = "nix-command flakes" ] && [ "$5" = "a path" ] || exit 98\
' "$TMP/bin/nix"
  run smm_nix eval --raw 'a path'
  [ "$status" -eq 0 ]
  calls | grep -qx 'nix --extra-experimental-features nix-command flakes eval --raw a path'
}
@test "sudo nix uses the same feature helper" {
  stub sudo 0
  run smm_nix --sudo run example -- switch
  [ "$status" -eq 0 ]
  calls | grep -qx 'sudo nix --extra-experimental-features nix-command flakes run example -- switch'
}
@test "healthy unrecorded Lix still requires a choice" {
  run step_nix_done
  [ "$status" -ne 0 ]
}
@test "keeping Lix shows both profiles records choice and skips future prompts" {
  run step_nix_run
  [ "$status" -eq 0 ]; [[ "$output" == *'nix profile list'*'nix-env -q'*legacy-package* ]]
  [ "$(cat "$SMM_STATE/nix-impl")" = lix ]
  calls | grep -q 'profile list'; calls | grep -qx 'nix-env -q'
  ! calls | grep -Eq 'repair|curl|uninstall'
  choose() { return 99; }
  run step_nix_done; [ "$status" -eq 0 ]
  run step_nix_run; [ "$status" -eq 0 ]
}
@test "Lix is never repaired by Determinate even when daemon fails" {
  stub nix 0 'Lix 2.95.2'
  sed -i '' '/exit 0/i\
case "$*" in *"store ping"*) exit 1 ;; esac\
' "$TMP/bin/nix"
  run step_nix_run
  [ "$status" -ne 0 ]; [[ "$output" == *Lix* ]]
  [ ! -f "$SMM_STATE/nix-impl" ]
  ! calls | grep -Eq 'repair|curl'
}
@test "switch without Lix uninstaller stops and links uninstall documentation" {
  choose() { echo 'switch to Determinate Nix'; }
  run step_nix_run
  [ "$status" -ne 0 ]; [[ "$output" == *'https://docs.lix.systems/manual/lix/stable/installation/uninstall.html'* ]]
  [ -d "$SMM_NIX_ROOT" ]
  ! calls | grep -Eq 'repair|curl'
}
@test "switch uninstalls Lix before installing Determinate without repair" {
  choose() { echo 'switch to Determinate Nix'; }
  stub lix-installer 0
  cp "$TMP/bin/lix-installer" "$SMM_NIX_ROOT/lix-installer"
  smm_install_determinate() { echo install-determinate >> "$TMP/calls.log"; stub nix 0 'nix (Determinate Nix) 3'; }
  run step_nix_run
  [ "$status" -eq 0 ]
  [ "$(calls | grep -E '^(lix-installer|install-determinate)' | tr '\n' '|')" = 'lix-installer uninstall|install-determinate|' ]
  [ "$(cat "$SMM_STATE/nix-impl")" = determinate ]
}
@test "failed Lix uninstall prevents install" {
  choose() { echo 'switch to Determinate Nix'; }
  stub lix-installer 1
  cp "$TMP/bin/lix-installer" "$SMM_NIX_ROOT/lix-installer"
  smm_install_determinate() { echo installed >> "$TMP/calls.log"; }
  run step_nix_run
  [ "$status" -ne 0 ]; ! calls | grep -qx installed
}
