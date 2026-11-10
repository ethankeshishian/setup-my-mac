#!/usr/bin/env bash

cmd_remove() (
  [ "$#" -eq 1 ] || { warn 'usage: smm remove <name>'; exit 2; }
  name=$1 repo=$(smm_repo)
  source=$(link_source "$name") || { warn "unknown link: $name"; exit 1; }
  target=$(link_field "$name" target) || exit 1
  if ! smm_safe_relative "$target" || ! smm_config_source_safe "$source"; then warn 'unsafe manifest path'; exit 1; fi
  dest="$HOME/$target" manifest="$repo/manifest/links.json"
  home=$(cd "$HOME" && pwd -P) || exit 1
  parent=$(cd "$(dirname "$dest")" && pwd -P) || exit 1
  case "$parent/" in "$home/"*) ;; *) warn 'target parent escapes HOME'; exit 1 ;; esac
  real_repo=$(cd "$repo" && pwd -P) || exit 1
  case "$parent/" in "$real_repo/"*) warn 'target is inside the repo'; exit 1 ;; esac
  smm_linked_to "$dest" "$repo/$source" || { warn 'target has drifted; reconcile it before removing'; exit 1; }
  # Refuse shared sources; removing one must never break a remaining link.
  resolved=$(links_resolved_json) || exit 1
  jq -e --arg name "$name" --arg source "$source" '
    all(.[]; . as $entry | .name == $name or (.source != $source and
      (.source | startswith($source + "/") | not) and ($source | startswith($entry.source + "/") | not)))' \
    <<< "$resolved" >/dev/null || { warn 'source overlaps another link'; exit 1; }
  answer=$(choose "Keep a normal copy at ~/$target?" 'keep file' delete) || exit 1
  case "$answer" in 'keep file'|delete) ;; *) exit 1 ;; esac
  backup=$(smm_backup_dir) || exit 1
  transaction=$(mktemp -d "$backup/remove.XXXXXX") || exit 1
  cp -a "$repo/$source" "$transaction/original" || exit 1
  cp "$manifest" "$transaction/links.json" || exit 1
  changed=0 complete=0
  # shellcheck disable=SC2329
  smm_remove_cleanup() {
    [ "$complete" -eq 0 ] || return 0
    if [ "$changed" -eq 1 ]; then
      cp "$transaction/links.json" "$manifest" || :
      if [ ! -e "$repo/$source" ]; then cp -a "$transaction/original" "$repo/$source" || :; fi
      if [ ! -e "$dest" ] && [ ! -L "$dest" ]; then ln -s "$repo/$source" "$dest" || :; fi
    fi
    warn "remove failed; backup retained at $transaction"
  }
  trap smm_remove_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  jq --arg name "$name" 'map(select(.name != $name))' "$manifest" > "$transaction/new.json" || exit 1
  changed=1
  cp "$transaction/new.json" "$manifest" || exit 1
  smm_run_apply || exit 1
  # home-manager may retain a previously managed link; remove only our link.
  if smm_linked_to "$dest" "$repo/$source"; then rm "$dest" || exit 1; fi
  [ ! -e "$dest" ] && [ ! -L "$dest" ] || { warn 'target changed during apply; backup retained'; exit 1; }
  if [ "$answer" = 'keep file' ]; then cp -a "$transaction/original" "$dest" || exit 1; fi
  # Leave deletion unstaged for the coordinator / next smm sync.
  rm -rf "${repo:?}/${source:?}" || exit 1
  complete=1
  log "removed $name (uncommitted); backup: $transaction/original"
)
