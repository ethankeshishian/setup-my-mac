#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  mkdir -p "$SMM_REPO/manifest"
  cp "$REPO/manifest/links.json" "$SMM_REPO/manifest/links.json"
  source "$REPO/smm/lib/common.sh"
  source "$REPO/smm/lib/health.sh"
  source "$REPO/smm/lib/reload.sh"
  stub aerospace 0 $'1\n2'
  stub sketchybar 0 '{"items":["space.1","space.2","clock"]}'
  stub pgrep 0 123
  stub tmux 0
  stub launchctl 0
}
@test "space count mismatch fails sketchybar" {
  stub sketchybar 0 '{"items":["space.1"]}'
  run smm_health
  [ "$status" -ne 0 ]
  [[ "$output" == *'fail sketchybar: space-count-mismatch'* ]]
  [ "$(smm_health_reason sketchybar)" = space-count-mismatch ]
}
@test "aerospace running but CLI fails means no-accessibility" {
  stub aerospace 1
  run smm_health
  [ "$status" -ne 0 ]
  [[ "$output" == *'fail aerospace: no-accessibility'* ]]
  [ "$(smm_health_reason aerospace)" = no-accessibility ]
}
@test "all healthy checks persist ok reasons" {
  smm_health
  [ "$(smm_health_reason aerospace)" = ok ]
  [ "$(smm_health_reason sketchybar)" = ok ]
}
@test "missing processes and malformed bar fail" {
  stub pgrep 1
  stub aerospace 1
  stub sketchybar 0 '{}'
  run smm_health
  [ "$status" -ne 0 ]
  [ "$(smm_health_reason aerospace)" = not-running ]
  [ "$(smm_health_reason borders)" = not-running ]
  [ "$(smm_health_reason karabiner)" = not-running ]
  [ "$(smm_health_reason sketchybar)" != ok ]
}
@test "reload skips tmux when no server" {
  stub tmux 1
  smm_reload tmux
  ! calls | grep -q source-file
}
@test "reload only named links" {
  smm_reload aerospace
  calls | grep -qx 'aerospace reload-config --no-gui'
  ! calls | grep -q sketchybar
}
@test "reload all and explicit borders" {
  smm_reload
  calls | grep -qx 'sketchybar --reload'
  calls | grep -qx "tmux source-file $HOME/.tmux.conf"
  ! calls | grep -q launchctl
  smm_reload borders
  calls | grep -qx "launchctl kickstart -k gui/$UID/org.nixos.jankyborders"
}
