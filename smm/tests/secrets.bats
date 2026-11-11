#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest"
  printf '%s\n' '[{"name":"weather","op_ref":"op://smm/weather/env","target":".config/sketchybar/scripts/weather.env.sh"}]' > "$SMM_REPO/manifest/secrets.json"
  printf '%s\n' '[{"name":"sketchybar","source":"config/sketchybar","target":".config/sketchybar","type":"dir"}]' > "$SMM_REPO/manifest/links.json"
  source "$REPO/smm/lib/common.sh"
  source "$REPO/smm/lib/secrets.sh"
  source "$REPO/smm/lib/scan.sh"
  stub op 0 'cached weather value'
}
# All git mutations below are confined to this test's fresh temporary repository.
commit_fixture() {
  git -C "$SMM_REPO" add -A
  git -C "$SMM_REPO" -c commit.gpgsign=false commit --quiet -m fixture
}
@test "existing target not re-read" {
  mkdir -p "$HOME/.config/sketchybar/scripts"
  printf existing > "$HOME/.config/sketchybar/scripts/weather.env.sh"
  smm_secrets_materialize
  [ -z "$(calls)" ]
}
@test "missing target written 600" {
  smm_secrets_materialize
  file="$HOME/.config/sketchybar/scripts/weather.env.sh"
  [ "$(cat "$file")" = 'cached weather value' ]
  [ "$(stat -c %a "$file" 2>/dev/null || stat -f %Lp "$file")" = 600 ]
  calls | grep -qx 'op read op://smm/weather/env'
}
@test "op signed out warns and succeeds" {
  stub op 1
  run smm_secrets_materialize
  [ "$status" -eq 0 ]
  [[ "$output" == *'weather: 1Password not signed in, skipping'* ]]
  [ ! -e "$HOME/.config/sketchybar/scripts/weather.env.sh" ]
}
@test "refresh replaces existing target and read failure preserves cache" {
  smm_secrets_materialize
  stub op 0 refreshed
  smm_secrets_materialize --refresh
  [ "$(cat "$HOME/.config/sketchybar/scripts/weather.env.sh")" = refreshed ]
  stub op 0
  sed_inplace 's/exit 0/if [ "$1" = read ]; then exit 1; fi/' "$TMP/bin/op"
  run smm_secrets_materialize --refresh
  [ "$status" -ne 0 ]
  [ "$(cat "$HOME/.config/sketchybar/scripts/weather.env.sh")" = refreshed ]
}
@test "scan blocks committed weather env script" {
  mkdir -p "$SMM_REPO/config/sketchybar/scripts"
  printf harmless > "$SMM_REPO/config/sketchybar/scripts/weather.env.sh"
  commit_fixture
  run smm_scan_outgoing HEAD~1..HEAD
  [ "$status" -ne 0 ]
  [[ "$output" == *'weather.env.sh'* ]]
}
@test "scan blocks mapped secret target even without env suffix" {
  jq '.[0].target = ".config/sketchybar/private.txt"' "$SMM_REPO/manifest/secrets.json" > "$TMP/secrets.json"
  cp "$TMP/secrets.json" "$SMM_REPO/manifest/secrets.json"
  mkdir -p "$SMM_REPO/config/sketchybar"
  printf harmless > "$SMM_REPO/config/sketchybar/private.txt"
  commit_fixture
  run smm_scan_outgoing HEAD~1..HEAD
  [ "$status" -ne 0 ]
  [[ "$output" == *'private.txt'* ]]
}
@test "scan blocks a fake ghp token" {
  printf 'token=ghp_%s\n' HAZtxslXT1IQrhbpy8qGuOziJdMmjnv2KCwP > "$SMM_REPO/token.txt"
  commit_fixture
  run smm_scan_outgoing HEAD~1..HEAD
  [ "$status" -ne 0 ]
  [[ "$output" != *"$(cat "$SMM_REPO/token.txt")"* ]]
}
@test "clean range passes" {
  printf clean > "$SMM_REPO/clean.txt"
  commit_fixture
  run smm_scan_outgoing HEAD~1..HEAD
  [ "$status" -eq 0 ]
}
@test "failed scanner and invalid revision fail closed" {
  printf clean > "$SMM_REPO/clean.txt"
  commit_fixture
  stub gitleaks 2 unavailable
  run smm_scan_outgoing HEAD~1..HEAD
  [ "$status" -ne 0 ]
  run smm_scan_outgoing not-a-revision
  [ "$status" -ne 0 ]
}
