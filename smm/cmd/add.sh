#!/usr/bin/env bash

cmd_add() (
  [ "$#" -ge 1 ] || { warn 'usage: smm add <path> [--name name]'; exit 2; }
  path=$1 name=''
  shift
  if [ "$#" -gt 0 ]; then
    [ "$#" -eq 2 ] && [ "$1" = --name ] || { warn 'usage: smm add <path> [--name name]'; exit 2; }
    name=$2
  fi
  [ -e "$path" ] || { warn 'path does not exist'; exit 1; }
  [ ! -L "$path" ] || { warn 'path is already linked'; exit 1; }
  path=$(cd -P "$(dirname "$path")" && printf '%s/%s\n' "$PWD" "$(basename "$path")") || exit 1
  home=$(cd "$HOME" && pwd -P) || exit 1
  repo=$(smm_repo) || exit 1
  real_repo=$(cd "$repo" && pwd -P) || exit 1
  case "$path" in "$home"/*) target=${path#"$home"/} ;; *) warn 'path must be under HOME'; exit 1 ;; esac
  case "$path/" in "$real_repo/"*) warn 'path is already in the repo'; exit 1 ;; esac
  smm_safe_relative "$target" || exit 1
  [ -n "$name" ] || name=$(basename "$path"); name=${name#.}
  case "$name" in ''|*[!a-zA-Z0-9_.-]*) warn 'invalid link name; use --name'; exit 1 ;; esac
  case "$target" in .config/*) source="config/${target#.config/}" ;; *) source="config/$(basename "$path")" ;; esac
  smm_config_source_safe "$source" || { warn 'unsafe source path'; exit 1; }
  dest="$repo/$source" manifest="$repo/manifest/links.json"
  [ ! -e "$dest" ] && [ ! -L "$dest" ] || { warn 'repo source already exists'; exit 1; }
  if ! jq -e --arg name "$name" --arg target "$target" --arg source "$source" '
    all(.[]; . as $entry | .name != $name and
      (.target != $target and (.target | startswith($target + "/") | not) and ($target | startswith($entry.target + "/") | not)) and
      (.source != $source and (.source | startswith($source + "/") | not) and ($source | startswith($entry.source + "/") | not)))' "$manifest" >/dev/null; then
    warn 'link name or path overlaps an existing entry'; exit 1
  fi
  kind='file'
  [ ! -d "$path" ] || kind=dir
  backup=$(smm_backup_dir) || exit 1
  transaction=$(mktemp -d "$backup/add.XXXXXX") || exit 1
  cp -a "$path" "$transaction/original" || exit 1
  cp "$manifest" "$transaction/links.json" || exit 1
  changed=0 removed=0 copied=0 complete=0
  # shellcheck disable=SC2329
  smm_add_cleanup() {
    [ "$complete" -eq 0 ] || return 0
    if [ "$changed" -eq 1 ]; then cp "$transaction/links.json" "$manifest" || :; fi
    if [ "$removed" -eq 1 ]; then
      rm -rf "${HOME:?}/${target:?}"
      cp -a "$transaction/original" "${HOME:?}/${target:?}" || warn "restore config from $transaction/original"
    fi
    [ "$copied" -eq 0 ] || rm -rf "$dest"
    warn "add failed; backup retained at $transaction"
  }
  trap smm_add_cleanup EXIT
  trap 'exit 130' INT
  trap 'exit 143' TERM
  mkdir -p "$(dirname "$dest")" || exit 1
  copied=1
  cp -a "$path" "$dest" || exit 1
  jq --arg name "$name" --arg source "$source" --arg target "$target" --arg type "$kind" \
    '. + [{name:$name,source:$source,target:$target,type:$type,validator:null,reload:null}]' \
    "$manifest" > "$transaction/new.json" || exit 1
  changed=1
  cp "$transaction/new.json" "$manifest" || exit 1
  removed=1
  rm -rf "${HOME:?}/${target:?}" || exit 1
  smm_run_apply || exit 1
  [ -L "${HOME:?}/${target:?}" ] && [ "$(readlink "${HOME:?}/${target:?}")" = "$dest" ] || { warn 'apply did not create the expected link'; exit 1; }
  complete=1
  rm -rf "$transaction"
  log "added $name (uncommitted)"
)
