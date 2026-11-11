#!/usr/bin/env bash

smm_raycast_vault_exists() {
  local vaults
  vaults=$(op vault list --format json 2>/dev/null) || return 1
  jq -e 'type == "array"' <<< "$vaults" >/dev/null || return 1
  if ! jq -e 'any(.[]; .name == "smm")' <<< "$vaults" >/dev/null; then return 3; fi
}
# Return 3 only for an absent document, distinct from an unavailable inventory.
smm_raycast_document() {
  local documents id
  smm_raycast_vault_exists || return "$?"
  documents=$(op document list --vault smm --format json 2>/dev/null) || return 1
  id=$(jq -er '[.[] | select(.title == "raycast-config")] |
    if length == 0 then empty elif length == 1 then .[0].id else error("duplicate raycast-config documents") end' <<< "$documents") || {
      [ "$(jq '[.[] | select(.title == "raycast-config")] | length' <<< "$documents" 2>/dev/null)" != 0 ] || return 3
      return 1
    }
  op item get "$id" --vault smm --format json 2>/dev/null
}
smm_raycast_revision() {
  jq -er 'select((.id | type) == "string" and (.version | type) == "number") | .id + ":" + (.version | tostring)'
}
smm_raycast_export_version() {
  jq -er '[.tags[]? | select(startswith("smm-raycast-version:")) | ltrimstr("smm-raycast-version:")] |
    select(length == 1) | .[0]'
}
step_raycast_done() {
  local document revision state
  op whoami >/dev/null 2>&1 || return 1
  document=$(smm_raycast_document) || return 1
  revision=$(smm_raycast_revision <<< "$document") || return 1
  state=$(smm_state_dir) || return 1
  [ -f "$state/raycast-imported" ] && [ "$(cat "$state/raycast-imported")" = "$revision" ] || return 1
  rm -f "$state/raycast-skipped"
}
step_raycast_run() (
  umask 077
  state=$(smm_state_dir) || exit 1
  skipped="$state/raycast-skipped"
  if ! op whoami >/dev/null 2>&1; then
    echo 'Raycast: 1Password not signed in; import skipped (degraded).' > "$skipped"
    cat "$skipped"; exit 0
  fi
  result=0
  document=$(smm_raycast_document) || result=$?
  if [ "$result" -eq 3 ]; then
    echo 'Raycast: no raycast-config document in vault smm; import skipped (degraded).' > "$skipped"
    cat "$skipped"; exit 0
  fi
  [ "$result" -eq 0 ] || { warn 'Raycast document metadata unavailable'; exit 1; }
  if ! exporting=$(smm_raycast_export_version <<< "$document") || ! smm_version_valid "$exporting"; then
    warn 'Raycast export version missing; re-export and run smm raycast save'; exit 1
  fi
  installed=$(smm_app_version raycast) || { warn 'Raycast not installed or version unreadable'; exit 1; }
  smm_version_at_least "$installed" "$exporting" || {
    warn "Raycast is $installed but config was exported from $exporting; update Raycast before importing"; exit 1;
  }
  id=$(jq -er .id <<< "$document") && revision=$(smm_raycast_revision <<< "$document") || exit 1
  acknowledgement=''; result=0
  acknowledgement=$(smm_answer_value user.raycast) || result=$?
  case "$result" in 0|4) ;; *) warn 'invalid answer user.raycast'; exit 1 ;; esac
  case "$acknowledgement" in done|'') ;; *) warn 'invalid answer user.raycast (allowed: done)'; exit 1 ;; esac
  if [ "$acknowledgement" = "done" ] && [ -f "$state/raycast-pending" ] &&
      [ "$(cat "$state/raycast-pending")" = "$revision" ]; then
    printf '%s\n' "$revision" > "$state/raycast-imported" || exit 1
    rm -f "$skipped" "$state/raycast-pending"
    exit 0
  fi
  tmp=$(mktemp -d) || exit 1
  trap 'rm -rf "$tmp"' EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  file="$tmp/import.rayconfig"
  op document get "$id" --vault smm > "$file" || exit 1
  chmod 600 "$file" || exit 1
  # Check metadata again: do not mark an import complete if the snapshot changed
  # while downloading, or open contents with a different exporting version.
  current=$(smm_raycast_document) || exit 1
  [ "$(smm_raycast_revision <<< "$current")" = "$revision" ] || { warn 'Raycast export changed; rerun setup'; exit 1; }
  open "$file" || exit 1
  printf '%s\n' "$revision" > "$state/raycast-pending" || exit 1
  log 'Raycast will ask for the export password in its import dialog.'
  # SMM_YES must never acknowledge an unattended import dialog.
  instruction='Imported?'
  smm_has_tty || instruction='Complete the Raycast password/import dialog, then confirm it was imported.'
  smm_user_wait raycast "$instruction" '' || exit "$?"
  printf '%s\n' "$revision" > "$state/raycast-imported" || exit 1
  rm -f "$skipped" "$state/raycast-pending"
)
smm_raycast_reminder() {
  local document exporting timestamp now
  op whoami >/dev/null 2>&1 || return 0
  document=$(smm_raycast_document) || return 0
  # The export date tag survives unrelated item edits. Older documents fall back
  # to 1Password's updated_at timestamp.
  exporting=$(jq -r '[.tags[]? | select(startswith("smm-raycast-exported:")) | ltrimstr("smm-raycast-exported:")][0] // empty' <<< "$document") || return 0
  if [ -n "$exporting" ]; then timestamp=$exporting;
  else
    timestamp=$(jq -er '.updated_at | fromdateiso8601' <<< "$document" 2>/dev/null) || return 0
  fi
  case "$timestamp" in ''|*[!0-9]*) return 0 ;; esac
  now=$(date +%s) || return 1
  if [ "$((now - timestamp))" -gt 2592000 ]; then
    echo 'Raycast export in 1Password is older than 30 days; re-export and run smm raycast save <file.rayconfig>.'
  fi
}
