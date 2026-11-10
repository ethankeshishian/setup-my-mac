#!/usr/bin/env bash

smm_prefs_bundle() {
  case "$1" in
    alttab) echo com.lwouis.alt-tab-macos ;;
    raycast) echo com.raycast.macos ;;
    *) warn 'supported apps: alttab raycast'; return 2 ;;
  esac
}
smm_prefs_name() {
  case "$1" in com.lwouis.alt-tab-macos) echo alttab ;; com.raycast.macos) echo raycast ;; *) return 2 ;; esac
}
smm_prefs_app() {
  case "$1" in alttab) echo AltTab ;; raycast) echo Raycast ;; *) return 2 ;; esac
}
smm_app_bundle() {
  local apps=${SMM_APPLICATIONS_DIR:-/Applications} app
  app=$(smm_prefs_app "$1") || return 2
  if [ -d "$apps/$app.app" ]; then printf '%s/%s.app\n' "$apps" "$app";
  else return 1; fi
}
smm_app_version() {
  local bundle version
  bundle=$(smm_app_bundle "$1") || return 1
  version=$(plutil -extract CFBundleShortVersionString raw -o - "$bundle/Contents/Info.plist") || return 1
  smm_version_valid "$version" || { warn 'invalid app version'; return 1; }
  printf '%s\n' "$version"
}
smm_version_valid() { [[ "$1" =~ ^[0-9]+(\.[0-9]+)*$ ]]; }
smm_version_at_least() {
  smm_version_valid "$1" && smm_version_valid "$2" || return 1
  awk -v a="$1" -v b="$2" 'BEGIN {
    na=split(a,x,"."); nb=split(b,y,".");
    for(i=1;i<=na || i<=nb;i++) { if(x[i]+0>y[i]+0)exit 0; if(x[i]+0<y[i]+0)exit 1 }
    exit 0
  }'
}
# Explicit keys from the inspected domain. Newly introduced keys need review;
# telemetry, identifiers, dates, window geometry and opaque blobs never qualify.
smm_prefs_allowlist() {
  case "$1" in
    alttab) printf '%s\n' alignThumbnails appearanceVisibility appsToShow crashPolicy \
      hideAppBadges hideColoredCircles hideSpaceNumberLabels hideThumbnails hideWindowlessApps \
      menubarIcon menubarIconShown screensToShow shortcutCount showFullscreenWindows \
      showHiddenWindows showMinimizedWindows showOnScreen showWindowlessApps showWindowlessApps10 \
      showWindowlessApps2 showWindowlessApps3 theme titleTruncation updatePolicy windowMaxWidthInRow ;;
    raycast) echo raycastGlobalHotkey ;;
    *) return 2 ;;
  esac
}
validate_prefs() {
  local file=$1 bundle name app captured installed
  bundle=$(basename "$file" .json)
  name=$(smm_prefs_name "$bundle") || { echo "unsupported prefs domain: $bundle"; return 1; }
  app=$(smm_prefs_app "$name") || return 1
  captured=$(jq -er --arg app "$app" '
    select(.app == $app and (.keys | type) == "object") | .captured_version | select(type == "string")' "$file") || return 1
  smm_version_valid "$captured" || { echo 'invalid captured_version'; return 1; }
  if ! smm_app_bundle "$name" >/dev/null; then echo 'skipped (app not installed)'; return 0; fi
  installed=$(smm_app_version "$name") || return 1
  if [ "$installed" = "$captured" ] || { [ "$name" = raycast ] && smm_version_at_least "$installed" "$captured"; }; then return 0; fi
  # shellcheck disable=SC2016 # Backticks are literal CLI instructions.
  printf '%s is %s but settings were captured from %s: open %s, check its settings, then run `smm capture %s`\n' "$app" "$installed" "$captured" "$app" "$name"
  return 1
}
smm_validate_prefs() {
  local root=$1 file bundle name result first failed=0 selected candidate
  shift
  [ "${SMM_SKIP_PREFS:-0}" != 1 ] || return 0
  for file in "$root"/manifest/prefs/*.json; do
    [ -f "$file" ] || continue
    bundle=$(basename "$file" .json)
    name=$(smm_prefs_name "$bundle") || { printf 'fail prefs: unsupported domain %s\n' "$bundle"; return 1; }
    selected=0
    [ "$#" -ne 0 ] || selected=1
    for candidate in "$@"; do case "$candidate" in prefs|"$name") selected=1 ;; esac; done
    [ "$selected" -eq 1 ] || continue
    if result=$(validate_prefs "$file" 2>&1); then
      case "$result" in skipped*) printf '%s: %s\n' "$name" "$result" ;; *) printf 'ok %s\n' "$name" ;; esac
    else
      first=${result%%$'\n'*}
      printf 'fail %s: %s\n' "$name" "${first:-invalid preferences}"
      SMM_FAILED_LINKS="${SMM_FAILED_LINKS:+$SMM_FAILED_LINKS }$name"
      failed=1
    fi
  done
  return "$failed"
}
smm_prefs_restart() {
  local app=$1
  pgrep -x "$app" >/dev/null || return 0
  osascript -e 'on run argv' -e 'tell application (item 1 of argv) to quit' -e 'end run' "$app" || return 1
  open -a "$app"
}
smm_prefs_relaunch() {
  local state file bundle name app hash saved
  state=$(smm_state_dir) || return 1
  for file in "$(smm_repo)"/manifest/prefs/*.json; do
    [ -f "$file" ] || continue
    bundle=$(basename "$file" .json)
    name=$(smm_prefs_name "$bundle") && app=$(smm_prefs_app "$name") || return 1
    hash=$(shasum -a 256 "$file" | awk '{print $1}') || return 1
    saved="$state/prefs/$bundle.hash"
    if [ -f "$saved" ] && [ "$(cat "$saved")" = "$hash" ]; then continue; fi
    if smm_app_bundle "$name" >/dev/null; then smm_prefs_restart "$app" || return 1; fi
    mkdir -p "$state/prefs" || return 1
    if [ -n "${SMM_TX:-}" ]; then smm_tx_arm "$saved" || return 1; fi
    printf '%s\n' "$hash" > "$saved" || return 1
  done
}
