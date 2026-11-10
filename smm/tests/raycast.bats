#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  export REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)" SMM_REPO="$TMP/repo" SMM_APPLICATIONS_DIR="$TMP/Applications"
  mkdir -p "$SMM_REPO/manifest" "$SMM_APPLICATIONS_DIR/Raycast.app/Contents"
  echo plist > "$SMM_APPLICATIONS_DIR/Raycast.app/Contents/Info.plist"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  stub plutil 0 2.11.1.0; stub open 0; stub op 0
  export SMM_TEST_DOCUMENT='{"id":"document1","title":"raycast-config","version":7,"updated_at":"2020-01-01T00:00:00Z","tags":["smm-raycast-version:2.11.1.0"]}'
  export SMM_TEST_VAULTS='[{"id":"vault1","name":"smm"}]'
  sed -i '' '/exit 0/i\
case "$1 $2" in\
"vault list") printf "%s\\n" "$SMM_TEST_VAULTS" ;;\
"item get") printf "%s\\n" "$SMM_TEST_DOCUMENT" ;;\
"document list") printf "[%s]\\n" "$SMM_TEST_DOCUMENT" ;;\
"document create"|"document edit") echo "{\"id\":\"document1\"}" ;;\
"document get") echo private-export ;;\
esac\
' "$TMP/bin/op"
  echo private-export > "$HOME/export.rayconfig"
}
@test "raycast save creates first document with exporting version tag" {
  export SMM_TEST_DOCUMENT=''
  run /bin/bash "$REPO/smm/bin/smm" raycast save "$HOME/export.rayconfig"
  [ "$status" -eq 0 ]
  calls | grep -Fq "op document create $(readlink -f "$HOME/export.rayconfig") --vault smm --title raycast-config --tags smm-raycast-version:2.11.1.0"
}
@test "raycast save edits existing document and refuses repo paths including symlinks" {
  run "$REPO/smm/bin/smm" raycast save "$HOME/export.rayconfig"; [ "$status" -eq 0 ]
  calls | grep -Fq 'op document edit document1'
  cp "$HOME/export.rayconfig" "$SMM_REPO/inside.rayconfig"
  ln -s "$SMM_REPO/inside.rayconfig" "$HOME/link.rayconfig"
  : > "$TMP/calls.log"
  for file in "$SMM_REPO/inside.rayconfig" "$HOME/link.rayconfig"; do
    run "$REPO/smm/bin/smm" raycast save "$file"; [ "$status" -eq 1 ]; [[ "$output" == *'inside the repo'* ]]
  done
  ! calls | grep -q 'op document'
}
@test "failed document inventory never creates duplicate" {
  stub op 1
  run "$REPO/smm/bin/smm" raycast save "$HOME/export.rayconfig"; [ "$status" -eq 1 ]
  ! calls | grep -q 'op document create'
}
@test "import downloads private rayconfig confirms and records current version" {
  confirm() { [ "$1" = 'Imported?' ]; }
  stub open 0
  sed -i '' '/exit 0/i\
[ "$(stat -f %Lp "$1")" = 600 ] || exit 99\
case "$1" in *.rayconfig) ;; *) exit 98 ;; esac\
printf "%s\\n" "$1" > "$TMP/import-path"\
' "$TMP/bin/open"
  run step_raycast_run; [ "$status" -eq 0 ]
  [ "$(cat "$SMM_STATE/raycast-imported")" = document1:7 ]
  [ ! -e "$(cat "$TMP/import-path")" ]
  run step_raycast_done; [ "$status" -eq 0 ]
  export SMM_TEST_DOCUMENT="${SMM_TEST_DOCUMENT/\"version\":7/\"version\":8}"
  run step_raycast_done; [ "$status" -eq 1 ]
}
@test "cancelled import cleans temp and never records completion" {
  confirm() { return 1; }
  run step_raycast_run; [ "$status" -eq 1 ]
  [ ! -e "$SMM_STATE/raycast-imported" ]
  file=$(calls | sed -n 's/^open //p')
  [ -n "$file" ]; [ ! -e "$file" ]
}
@test "import refuses older Raycast before opening file" {
  stub plutil 0 2.10.1.0
  run step_raycast_run; [ "$status" -eq 1 ]; [[ "$output" == *'exported from 2.11.1.0'* ]]
  ! calls | grep -q '^open '
}
@test "missing export version fails safely and unsigned or missing document degrades" {
  export SMM_TEST_DOCUMENT='{"id":"document1","title":"raycast-config","version":7,"tags":[]}'
  run step_raycast_run; [ "$status" -eq 1 ]; ! calls | grep -q '^open '
  stub op 1
  run step_raycast_run; [ "$status" -eq 0 ]; [[ "$output" == *'1Password not signed in'* ]]
  export SMM_TEST_DOCUMENT=''
  stub op 0 '[]'
  run step_raycast_run; [ "$status" -eq 0 ]; [[ "$output" == *'no raycast-config document'* ]]
}
@test "setup Raycast follows signin and old export generates reminder" {
  smm_setup_steps
  [[ " ${SETUP_STEPS[*]} " == *' signin raycast '* ]]
  run smm_raycast_reminder; [ "$status" -eq 0 ]; [[ "$output" == *'older than 30 days'*'re-export'* ]]
  export SMM_TEST_DOCUMENT="${SMM_TEST_DOCUMENT/2020-01-01T00:00:00Z/2099-01-01T00:00:00Z}"
  run smm_raycast_reminder; [ "$status" -eq 0 ]; [ -z "$output" ]
}
@test "missing smm vault is a degraded import and save creates it" {
  stub op 0
  sed -i '' '/exit 0/i\
case "$1 $2" in\
"vault list") echo "[]" ;;\
"document list") exit 1 ;;\
esac\
' "$TMP/bin/op"
  run step_raycast_run; [ "$status" -eq 0 ]; [[ "$output" == *'no raycast-config document'* ]]
  run cmd_raycast save "$HOME/export.rayconfig"; [ "$status" -eq 0 ]
  calls | grep -qx 'op vault create smm'
}
@test "document download failure never opens private temporary file" {
  stub op 0
  sed -i '' '/exit 0/i\
case "$1 $2" in\
"vault list") printf "%s\\n" "$SMM_TEST_VAULTS" ;;\
"document list") printf "[%s]\\n" "$SMM_TEST_DOCUMENT" ;;\
"item get") printf "%s\\n" "$SMM_TEST_DOCUMENT" ;;\
"document get") echo private-export; exit 1 ;;\
esac\
' "$TMP/bin/op"
  run step_raycast_run; [ "$status" -eq 1 ]; ! calls | grep -q '^open '
}
@test "status shows re-export reminder and successful done check clears degraded note" {
  make_repo "$SMM_REPO"
  echo '[]' > "$SMM_REPO/manifest/links.json"
  echo '[]' > "$SMM_REPO/manifest/secrets.json"
  echo '{"taps":[],"brews":[],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  stub brew 0; stub gh 0
  run cmd_status; [ "$status" -eq 0 ]; [[ "$output" == *'older than 30 days'* ]]
  echo document1:7 > "$SMM_STATE/raycast-imported"
  echo degraded > "$SMM_STATE/raycast-skipped"
  run step_raycast_done; [ "$status" -eq 0 ]; [ ! -e "$SMM_STATE/raycast-skipped" ]
}
@test "interrupted import removes temporary export before returning" {
  stub open 0
  sed -i '' '/exit 0/i\
printf "%s\\n" "$1" > "$TMP/import-path"\
kill -TERM "$PPID"\
' "$TMP/bin/open"
  run step_raycast_run; [ "$status" -eq 143 ]
  [ ! -e "$(cat "$TMP/import-path")" ]; [ ! -e "$SMM_STATE/raycast-imported" ]
}
@test "save refuses a repo symlink even when its target is outside" {
  ln -s "$HOME/export.rayconfig" "$SMM_REPO/export.rayconfig"
  run cmd_raycast save "$SMM_REPO/export.rayconfig"
  [ "$status" -eq 1 ]; [[ "$output" == *'inside the repo'* ]]
}
