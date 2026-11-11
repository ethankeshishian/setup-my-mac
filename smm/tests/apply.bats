#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)"
  export SMM_REPO="$TMP/repo"
  make_repo "$SMM_REPO"
  mkdir -p "$SMM_REPO/manifest" "$SMM_REPO/config" "$SMM_REPO/result/sw/bin"
  printf '%s\n' '[{"name":"aerospace","source":"config/aero","target":".aerospace.toml","validator":"aerospace","reload":"aerospace"},{"name":"sketchybar","source":"config/bar","target":".bar","validator":null,"reload":"sketchybar"}]' > "$SMM_REPO/manifest/links.json"
  printf '%s\n' '{"taps":[],"brews":[],"casks":[]}' > "$SMM_REPO/manifest/homebrew.json"
  printf '[]\n' > "$SMM_REPO/manifest/secrets.json"
  printf original > "$SMM_REPO/config/aero"
  mkdir "$SMM_REPO/config/bar"
  ln -s "$SMM_REPO/config/aero" "$HOME/.aerospace.toml"
  ln -s "$SMM_REPO/config/bar" "$HOME/.bar"
  for lib in "$REPO"/smm/lib/*.sh; do source "$lib"; done
  stub aerospace 0 $'1\n2'
  stub sketchybar 0 '{"items":["space.1","space.2"]}'
  stub brew 0
  stub gh 0
  stub launchctl 0
  stub scutil 0 Test-Mac
  stub pgrep 0
  stub sudo 0
  sed_inplace 's/exit 0/exec "$@"/' "$TMP/bin/sudo"
  stub darwin-rebuild 0 '42 date (current)'
  smm_nix_inputs_hash > "$SMM_STATE/applied.hash"
}
@test "broken config is not reloaded and file untouched" {
  stub aerospace 0
  sed_inplace '/exit 0/i\
if [[ "$*" == *--dry-run* ]]; then echo broken; exit 1; fi\
' "$TMP/bin/aerospace"
  before=$(shasum "$SMM_REPO/config/aero")
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *'not reloaded aerospace: broken'* ]]
  ! calls | grep -qx 'aerospace reload-config --no-gui'
  calls | grep -qx 'sketchybar --reload'
  [ "$(shasum "$SMM_REPO/config/aero")" = "$before" ]
}
@test "unchanged inputs skip build" {
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 0 ]
  ! calls | grep -q 'darwin-rebuild build'
}
@test "health failure rolls back to previous generation" {
  rm "$SMM_STATE/applied.hash"
  stub pgrep 1
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  calls | grep -qx 'darwin-rebuild switch --switch-generation 42'
}
@test "build failure never switches" {
  rm "$SMM_STATE/applied.hash"
  stub darwin-rebuild 0 '42 date (current)'
  sed_inplace '/exit 0/i\
[ "$1" != build ] || exit 1\
' "$TMP/bin/darwin-rebuild"
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  ! calls | grep -q 'darwin-rebuild switch'
}
@test "switch failure rolls back" {
  rm "$SMM_STATE/applied.hash"
  stub sudo 1
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  calls | grep -q 'switch --switch-generation 42'
}
@test "status clean" {
  git -C "$SMM_REPO" add -A
  git -C "$SMM_REPO" -c commit.gpgsign=false commit -qm fixture
  run "$REPO/smm/bin/smm" status
  [ "$status" -eq 0 ]
  [ "$output" = clean ]
}
@test "status reports a link that became a real file and degraded signin" {
  rm "$HOME/.aerospace.toml"
  printf drift > "$HOME/.aerospace.toml"
  stub gh 1
  run "$REPO/smm/bin/smm" status
  [ "$status" -eq 0 ]
  [[ "$output" == *'broken links:'*'aerospace'* ]]
  [[ "$output" == *'GitHub not signed in'* ]]
}
@test "cancelled accessibility wait rolls back without finalizing" {
  rm "$SMM_STATE/applied.hash"
  stub aerospace 0
  sed_inplace '/exit 0/i\
[ "$1" != list-workspaces ] || exit 1\
' "$TMP/bin/aerospace"
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *Accessibility* ]]
  calls | grep -q switch-generation
}
@test "invalid manifest aborts before build or reload" {
  printf broken > "$SMM_REPO/manifest/links.json"
  run "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  ! calls | grep -Eq 'darwin-rebuild (build|switch)|sketchybar --reload'
}
@test "adopted package is included in the activated build" {
  source "$REPO/smm/cmd/apply.sh"
  rm "$SMM_STATE/applied.hash"
  smm_build() { cp "$SMM_REPO/manifest/homebrew.json" "$TMP/built-manifest"; }
  smm_brew_resolve() { printf '{"taps":[],"brews":["adopted"],"casks":[]}\n' > "$SMM_REPO/manifest/homebrew.json"; }
  smm_switch() { cmp "$TMP/built-manifest" "$SMM_REPO/manifest/homebrew.json"; }
  run cmd_apply
  [ "$status" -eq 0 ]
}
@test "all failed validators reload nothing under bash 3 nounset" {
  jq '[.[0]]' "$SMM_REPO/manifest/links.json" > "$TMP/one.json"
  cp "$TMP/one.json" "$SMM_REPO/manifest/links.json"
  smm_nix_inputs_hash > "$SMM_STATE/applied.hash"
  stub aerospace 1 broken
  run /bin/bash "$REPO/smm/bin/smm" apply
  [ "$status" -eq 1 ]
  [[ "$output" == *'not reloaded aerospace: broken'* ]]
  ! calls | grep -qx 'aerospace reload-config --no-gui'
}
@test "remaining service failure after permission grant rolls back" {
  source "$REPO/smm/cmd/apply.sh"
  rm "$SMM_STATE/applied.hash"
  stub aerospace 0
  sed_inplace '/exit 0/i\
[ "$1" != list-workspaces ] || exit 1\
' "$TMP/bin/aerospace"
  stub pgrep 0
  sed_inplace '/exit 0/i\
[ "$2" != borders ] || exit 1\
' "$TMP/bin/pgrep"
  smm_wait_permission() { stub aerospace 0 $'1\n2'; }
  run cmd_apply
  [ "$status" -eq 1 ]
  calls | grep -qx 'darwin-rebuild switch --switch-generation 42'
}
@test "status reports ahead behind undeclared packages and missing secrets" {
  git -C "$SMM_REPO" add -A
  git -C "$SMM_REPO" -c commit.gpgsign=false commit -qm baseline
  git clone -q --bare "$SMM_REPO" "$TMP/status-remote.git"
  git --git-dir="$TMP/status-remote.git" fetch -q "$SMM_REPO" HEAD:refs/heads/main
  git -C "$SMM_REPO" remote add origin "$TMP/status-remote.git"
  git clone -q -b main "$TMP/status-remote.git" "$TMP/status-peer"
  git -C "$TMP/status-peer" config user.name 'Smm Test'
  git -C "$TMP/status-peer" config user.email test@example.invalid
  printf remote > "$TMP/status-peer/remote-file"
  git -C "$TMP/status-peer" add -A
  git -C "$TMP/status-peer" -c commit.gpgsign=false commit -qm remote
  git --git-dir="$TMP/status-remote.git" fetch -q "$TMP/status-peer" HEAD:refs/heads/main
  printf local > "$SMM_REPO/local-file"
  git -C "$SMM_REPO" add -A
  git -C "$SMM_REPO" -c commit.gpgsign=false commit -qm local
  printf '%s\n' '[{"name":"weather","target":"missing.env.sh"}]' > "$SMM_REPO/manifest/secrets.json"
  stub brew 0 $'Would uninstall formulae:\n  example'
  run "$REPO/smm/bin/smm" status
  [ "$status" -eq 0 ]
  [[ "$output" == *'origin/main: 1 ahead, 1 behind'* ]]
  [[ "$output" == *'undeclared Homebrew packages:'*'brew example'* ]]
  [[ "$output" == *'missing secret: weather'* ]]
}

@test "apply relaunches changed running prefs after switch and skips next unchanged apply" {
  mkdir -p "$SMM_REPO/manifest/prefs" "$SMM_APPLICATIONS_DIR/AltTab.app/Contents"
  echo plist > "$SMM_APPLICATIONS_DIR/AltTab.app/Contents/Info.plist"
  echo '{"app":"AltTab","captured_version":"10.12.0","keys":{"theme":"0"}}' > "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
  stub plutil 0 10.12.0; stub osascript 0; stub open 0
  run /bin/bash "$REPO/smm/bin/smm" apply; [ "$status" -eq 0 ]
  calls | grep -qx 'open -a AltTab'
  switch_line=$(calls | awk '/^darwin-rebuild switch --flake/ {print NR}')
  open_line=$(calls | awk '/^open -a AltTab$/ {print NR}')
  [ "$open_line" -gt "$switch_line" ]
  : > "$TMP/calls.log"
  run "$REPO/smm/bin/smm" apply; [ "$status" -eq 0 ]
  ! calls | grep -q '^open '
}
@test "failed build never relaunches preferences apps" {
  mkdir -p "$SMM_REPO/manifest/prefs" "$SMM_APPLICATIONS_DIR/AltTab.app/Contents"
  echo plist > "$SMM_APPLICATIONS_DIR/AltTab.app/Contents/Info.plist"
  echo '{"app":"AltTab","captured_version":"10.12.0","keys":{}}' > "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
  stub plutil 0 10.12.0
  stub darwin-rebuild 1
  run "$REPO/smm/bin/smm" apply; [ "$status" -eq 1 ]
  ! calls | grep -q '^open '
  [ ! -d "$SMM_STATE/prefs" ]
}
