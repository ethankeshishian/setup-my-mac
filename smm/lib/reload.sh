#!/usr/bin/env bash

smm_reload() {
  local name action names status=0
  if [ "$#" -eq 0 ]; then
    names=$(link_names) || return 1
    # Manifest names are single identifiers; read one per line without splitting paths.
    while IFS= read -r name; do smm_reload "$name" || status=1; done <<< "$names"
    return "$status"
  fi
  for name in "$@"; do
    if [ "$name" = borders ]; then action=borders;
    else action=$(link_field "$name" reload) || action=''; fi
    case "$action" in
      aerospace) aerospace reload-config --no-gui || status=1 ;;
      sketchybar) sketchybar --reload || status=1 ;;
      tmux)
        if tmux info >/dev/null 2>&1; then tmux source-file "$HOME/.tmux.conf" || status=1; fi ;;
      borders) launchctl kickstart -k "gui/$UID/org.nixos.jankyborders" || status=1 ;;
      '') ;;
      *) warn "unknown reload action: $action"; status=1 ;;
    esac
  done
  return "$status"
}
