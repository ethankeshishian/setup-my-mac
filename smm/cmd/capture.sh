#!/usr/bin/env bash

cmd_capture() (
  [ "$#" -eq 1 ] || { warn 'usage: smm capture <alttab|raycast>'; exit 2; }
  name=$1
  bundle=$(smm_prefs_bundle "$name") && app=$(smm_prefs_app "$name") || exit 2
  version=$(smm_app_version "$name") || { warn "$app not installed or version unreadable"; exit 1; }
  umask 077
  tmp=$(mktemp -d) || exit 1
  dest=''
  trap 'rm -rf "$tmp"; [ -z "$dest" ] || rm -f "$dest"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  defaults export "$bundle" - > "$tmp/prefs.plist" || exit 1
  plutil -convert json -o "$tmp/prefs.json" "$tmp/prefs.plist" || exit 1
  # plutil writes to the supplied output path, rather than stdout.
  allowed=$(smm_prefs_allowlist "$name" | jq -Rsc 'split("\n") | map(select(length > 0))') || exit 1
  mkdir -p "$(smm_repo)/manifest/prefs" || exit 1
  dest=$(mktemp "$(smm_repo)/manifest/prefs/.capture.XXXXXX") || exit 1
  jq --arg name "$name" --arg app "$app" --arg version "$version" --argjson allowed "$allowed" '
    with_entries(select(.key as $key | $allowed | index($key))) |
    with_entries(select((.value | type) == "string" or (.value | type) == "number" or (.value | type) == "boolean")) |
    (if $name == "alttab" then . + {updatePolicy:"0",SUEnableAutomaticChecks:false,SUAutomaticallyUpdate:false} else . end) |
    {app:$app,captured_version:$version,keys:.}' "$tmp/prefs.json" > "$dest" || exit 1
  mv "$dest" "$(smm_repo)/manifest/prefs/$bundle.json" || exit 1
  dest=''
  log "Captured $app $version preferences; review and commit manifest/prefs/$bundle.json."
)
