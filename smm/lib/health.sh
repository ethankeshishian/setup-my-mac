#!/usr/bin/env bash

smm_health() {
  local state workspaces='' aerospace_reason=ok sketchybar_reason=ok borders_reason=ok karabiner_reason=ok
  local bar='' spaces count status=0
  state=$(smm_state_dir) || return 1
  if ! workspaces=$(aerospace list-workspaces --all 2>/dev/null); then
    if pgrep -x AeroSpace >/dev/null; then aerospace_reason=no-accessibility; else aerospace_reason=not-running; fi
  fi
  if ! bar=$(sketchybar --query bar 2>/dev/null); then
    sketchybar_reason=not-running
  elif ! spaces=$(jq -er '.items | if type == "array" then map(select(type == "string" and startswith("space."))) | length else error("missing items") end' <<< "$bar" 2>/dev/null); then
    sketchybar_reason=invalid-response
  elif [ "$aerospace_reason" != ok ]; then
    sketchybar_reason='workspaces-unavailable'
  else
    count=$(awk 'NF {n++} END {print n+0}' <<< "$workspaces")
    [ "$count" -eq "$spaces" ] || sketchybar_reason=space-count-mismatch
  fi
  pgrep -x borders >/dev/null || borders_reason=not-running
  pgrep -f karabiner_console_user_server >/dev/null || karabiner_reason=not-running
  jq -n --arg aerospace "$aerospace_reason" --arg sketchybar "$sketchybar_reason" \
    --arg borders "$borders_reason" --arg karabiner "$karabiner_reason" \
    '{aerospace:$aerospace, sketchybar:$sketchybar, borders:$borders, karabiner:$karabiner}' > "$state/health.json" || return 1
  local app reason
  for app in aerospace sketchybar borders karabiner; do
    reason=$(smm_health_reason "$app") || return 1
    if [ "$reason" = ok ]; then printf 'ok %s\n' "$app";
    else printf 'fail %s: %s\n' "$app" "$reason"; status=1; fi
  done
  return "$status"
}
smm_health_reason() {
  jq -er --arg app "$1" '.[$app] // empty' "$(smm_state_dir)/health.json"
}
