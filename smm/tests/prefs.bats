#!/usr/bin/env bats
load helpers
setup() {
  setup_tmp
  export REPO="$(cd "$BATS_TEST_DIRNAME/../.." && pwd)" SMM_REPO="$TMP/repo" SMM_APPLICATIONS_DIR="$TMP/Applications"
  mkdir -p "$SMM_REPO/manifest/prefs" "$SMM_APPLICATIONS_DIR"
  echo '[]' > "$SMM_REPO/manifest/links.json"
  for file in "$REPO"/smm/lib/*.sh "$REPO"/smm/cmd/*.sh; do source "$file"; done
  stub plutil 0 10.12.0
  stub defaults 0 '<plist/>'
  stub open 0; stub osascript 0
  echo '{"app":"AltTab","captured_version":"10.12.0","keys":{"theme":"0"}}' > "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
}
app() { mkdir -p "$SMM_APPLICATIONS_DIR/$1.app/Contents"; echo plist > "$SMM_APPLICATIONS_DIR/$1.app/Contents/Info.plist"; }
@test "prefs validates each app and missing apps are skipped" {
  run "$REPO/smm/bin/smm" validate prefs
  [ "$status" -eq 0 ]; [[ "$output" == *'alttab: skipped (app not installed)'* ]]
  app AltTab
  run "$REPO/smm/bin/smm" validate alttab
  [ "$status" -eq 0 ]; [[ "$output" == *'ok alttab'* ]]
  calls | grep -Fq "$SMM_APPLICATIONS_DIR/AltTab.app/Contents/Info.plist"
}
@test "AltTab lookup ignores Nix Apps and prefers the Homebrew app" {
  app 'Nix Apps/AltTab'
  run smm_app_bundle alttab; [ "$status" -eq 1 ]
  app AltTab
  run smm_app_bundle alttab
  [ "$status" -eq 0 ]; [ "$output" = "$SMM_APPLICATIONS_DIR/AltTab.app" ]
}
@test "AltTab rejects older versions too" {
  app AltTab; stub plutil 0 6.29.0
  run smm_validate "$SMM_REPO" alttab
  [ "$status" -eq 1 ]
  [[ "$output" == *'AltTab is 6.29.0 but settings were captured from 10.12.0'* ]]
}
@test "AltTab mismatch gives precise recapture instructions and records failure" {
  app AltTab; stub plutil 0 11.7.1
  run smm_validate "$SMM_REPO"
  [ "$status" -eq 1 ]
  [[ "$output" == *'AltTab is 11.7.1 but settings were captured from 10.12.0: open AltTab, check its settings, then run `smm capture alttab`'* ]]
  smm_validate "$SMM_REPO" >/dev/null || :
  [ "$SMM_FAILED_LINKS" = alttab ]
}
@test "Raycast allows newer versions and rejects older using numeric components" {
  app Raycast
  echo '{"app":"Raycast","captured_version":"2.11.1.0","keys":{"raycastGlobalHotkey":"Command-49"}}' > "$SMM_REPO/manifest/prefs/com.raycast.macos.json"
  for version in 2.11.1.0 2.12.0 2.100.0; do
    stub plutil 0 "$version"; run smm_validate "$SMM_REPO" raycast; [ "$status" -eq 0 ]
  done
  stub plutil 0 2.10.1.0
  run smm_validate "$SMM_REPO" raycast; [ "$status" -eq 1 ]
  [[ "$output" == *'smm capture raycast'* ]]
}
@test "capture filters keys and disables AltTab updater without committing" {
  app AltTab
  stub plutil 0 '{"theme":"2","crashPolicy":"1","SUEnableAutomaticChecks":true,"updatePolicy":"2","MSAppCenterInstallId":"private","NSWindow Frame SettingsWindow":"frame","preferencesVersion":"old","settingsWindowShownOnFirstLaunch":true,"unknownID":"private","SULastCheckTime":"date","blob":{"data":"secret"}}'
  # Distinguish version extraction from conversion without touching real defaults.
  sed -i '' '/if \[ -n "$stub_stdout" \]/i\
if [ "$1" = -extract ]; then echo 10.12.0; exit 0; fi\
if [ "$1" = -convert ]; then printf "%s\\n" "$stub_stdout" > "$4"; exit 0; fi\
' "$TMP/bin/plutil"
  run /bin/bash "$REPO/smm/bin/smm" capture alttab
  [ "$status" -eq 0 ]
  jq -e '.captured_version == "10.12.0" and .keys == {theme:"2",crashPolicy:"1",updatePolicy:"0",SUEnableAutomaticChecks:false,SUAutomaticallyUpdate:false}' "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
  calls | grep -qx 'defaults export com.lwouis.alt-tab-macos -'
  ! calls | grep -q '^git '
}
@test "Raycast capture keeps only global hotkey and requires installed app" {
  run "$REPO/smm/bin/smm" capture raycast; [ "$status" -eq 1 ]
  app Raycast
  stub plutil 0 '{"raycastGlobalHotkey":"Command-49","secret":"private"}'
  sed -i '' '/if \[ -n "$stub_stdout" \]/i\
if [ "$1" = -extract ]; then echo 2.11.1.0; exit 0; fi\
if [ "$1" = -convert ]; then printf "%s\\n" "$stub_stdout" > "$4"; exit 0; fi\
' "$TMP/bin/plutil"
  run "$REPO/smm/bin/smm" capture raycast; [ "$status" -eq 0 ]
  jq -e '.keys == {raycastGlobalHotkey:"Command-49"}' "$SMM_REPO/manifest/prefs/com.raycast.macos.json"
}
@test "failed capture leaves previous manifest intact" {
  app AltTab; stub defaults 1
  cp "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json" "$TMP/before"
  run "$REPO/smm/bin/smm" capture alttab; [ "$status" -eq 1 ]
  cmp "$TMP/before" "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
}
@test "prefs content participates in Nix hash" {
  before=$(smm_nix_inputs_hash)
  echo ' ' >> "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
  [ "$(smm_nix_inputs_hash)" != "$before" ]
}
@test "changed prefs relaunch only running apps and hashes suppress repeat relaunch" {
  app AltTab
  run smm_prefs_relaunch; [ "$status" -eq 0 ]
  calls | grep -q '^osascript .*AltTab'
  calls | grep -qx 'open -a AltTab'
  : > "$TMP/calls.log"
  run smm_prefs_relaunch; [ "$status" -eq 0 ]; ! calls | grep -q '^open '
  echo ' ' >> "$SMM_REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
  stub pgrep 1
  run smm_prefs_relaunch; [ "$status" -eq 0 ]; ! calls | grep -q '^open '
}
@test "failed relaunch does not advance prefs hash" {
  app AltTab; stub open 1
  run smm_prefs_relaunch; [ "$status" -eq 1 ]
  stub open 0
  run smm_prefs_relaunch; [ "$status" -eq 0 ]
  [ "$(calls | grep -c '^open -a AltTab$')" -eq 2 ]
}
@test "AltTab permissions open both panes and require explicit confirmation" {
  run smm_wait_permission alttab; [ "$status" -eq 1 ]
  calls | grep -q Privacy_Accessibility; calls | grep -q Privacy_ScreenCapture
  confirm() { [ "$1" = 'AltTab has Accessibility AND Screen Recording. Done?' ]; }
  run smm_wait_permission alttab; [ "$status" -eq 0 ]
  run smm_permission_granted alttab; [ "$status" -ne 0 ]
}
@test "setup preserves the declared AltTab cask without deduping or replacing it" {
  cp "$REPO/manifest/nix-packages.json" "$SMM_REPO/manifest/nix-packages.json"
  cp "$REPO/manifest/homebrew.json" "$SMM_REPO/manifest/homebrew.json"
  cp "$SMM_REPO/manifest/homebrew.json" "$TMP/before"
  stub brew 0
  sed -i '' '/if \[ -n "$stub_stdout" \]/i\
if [ "$*" = "list --cask" ]; then echo alt-tab; fi\
' "$TMP/bin/brew"
  run smm_brew_duplicates; [ "$status" -eq 0 ]; [ -z "$output" ]
  run step_brew_adopt_run; [ "$status" -eq 0 ]
  run step_dedupe_run; [ "$status" -eq 0 ]
  run smm_setup_restore_brew; [ "$status" -eq 0 ]
  cmp "$TMP/before" "$SMM_REPO/manifest/homebrew.json"
  ! calls | grep -Eq '^brew (uninstall|install)|^osascript |^open '
}
@test "AltTab snapshot records 10.12.0 with all update checks disabled" {
  jq -e '.captured_version == "10.12.0" and .keys.updatePolicy == "0" and
    .keys.SUEnableAutomaticChecks == false and .keys.SUAutomaticallyUpdate == false' \
    "$REPO/manifest/prefs/com.lwouis.alt-tab-macos.json"
}
