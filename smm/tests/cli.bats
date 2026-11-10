#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/manifest"
  printf '%s\n' '[{"name":"one","source":"config/one","target":".one","validator":null,"reload":null}]' > "$SMM_REPO/manifest/links.json"
}
@test "help lists every command" {
  run "$REPO/smm/bin/smm" --help
  [ "$status" -eq 0 ]
  for name in setup apply sync add remove status upgrade undo validate; do [[ "$output" == *"$name"* ]]; done
}
@test "unknown command exits 2" {
  run "$REPO/smm/bin/smm" nonexistent
  [ "$status" -eq 2 ]
}
@test "link_field reads manifest" {
  source "$REPO/smm/lib/common.sh"
  [ "$(link_field one source)" = config/one ]
  [ "$(link_names)" = one ]
}
@test "confirm without tty returns 1" {
  source "$REPO/smm/lib/common.sh"
  run confirm 'Continue?'
  [ "$status" -eq 1 ]
}
@test "yes confirms and state directory is created" {
  source "$REPO/smm/lib/common.sh"
  SMM_YES=1 confirm 'Continue?'
  [ "$(smm_state_dir)" = "$SMM_STATE" ]
  [ -d "$SMM_STATE" ]
}
@test "global yes reaches the dispatched command from the repo binary" {
  mkdir -p "$TMP/app/bin" "$TMP/app/lib" "$TMP/app/cmd"
  cp "$REPO/smm/bin/smm" "$TMP/app/bin/smm"
  cp "$REPO/smm/lib/common.sh" "$TMP/app/lib/common.sh"
  printf 'cmd_status() { confirm "Continue?"; }\n' > "$TMP/app/cmd/status.sh"
  run "$TMP/app/bin/smm" -y status
  [ "$status" -eq 0 ]
  run "$TMP/app/bin/smm" -y -y status
  [ "$status" -eq 0 ]
}
