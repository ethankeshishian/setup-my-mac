#!/usr/bin/env bash

smm_repo() { printf '%s\n' "${SMM_REPO:-$HOME/Repos/setup-my-mac}"; }
smm_state_dir() {
  local state=${SMM_STATE:-$HOME/.local/state/smm}
  mkdir -p "$state" || return
  printf '%s\n' "$state"
}
log() { printf '%s\n' "$*"; }
warn() { printf 'smm: %s\n' "$*" >&2; }
die() { warn "$1"; exit "${2:-1}"; }
confirm() {
  local answer
  [ "${SMM_YES:-0}" = 1 ] && return 0
  smm_has_tty || return 1
  printf '%s [y/N] ' "$1" >&2
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in y|Y|yes|YES) return 0 ;; *) return 1 ;; esac
}
choose() {
  local question=$1 option answer index=0
  shift
  smm_has_tty || return 1
  printf '%s\n' "$question" >&2
  for option in "$@"; do
    index=$((index + 1))
    printf '%s) %s\n' "$index" "$option" >&2
  done
  IFS= read -r answer </dev/tty || return 1
  case "$answer" in ''|*[!0-9]*) return 1 ;; esac
  [ "$answer" -gt 0 ] && [ "$answer" -le "$#" ] || return 1
  index=0
  for option in "$@"; do
    index=$((index + 1))
    if [ "$index" -eq "$answer" ]; then printf '%s\n' "$option"; return 0; fi
  done
}
links_json() { cat "$(smm_repo)/manifest/links.json"; }
link_field() {
  links_json | jq -er --arg name "$1" --arg field "$2" '.[] | select(.name == $name) | .[$field] // empty'
}
link_names() { links_json | jq -r '.[].name'; }

# Resolve against the manifest being inspected (including sync worktrees).
link_source() {
  local name=$1 root=${2:-$(smm_repo)} source host
  source=$(jq -er --arg name "$name" '.[] | select(.name == $name) | .source' "$root/manifest/links.json") || return 1
  case "$source" in *'{host}'*)
    host=$(smm_host) || return 1
    case "$host" in ''|-*|*[!a-zA-Z0-9-]*) warn 'invalid host name'; return 1 ;; esac
    source=${source//\{host\}/$host}
    ;;
  esac
  smm_safe_relative "$source" || return 1
  printf '%s\n' "$source"
}

links_resolved_json() {
  local root=${1:-$(smm_repo)} entries names name source
  entries=$(cat "$root/manifest/links.json") || return 1
  names=$(jq -r '.[].name' <<< "$entries") || return 1
  while IFS= read -r name; do
    [ -n "$name" ] || continue
    source=$(link_source "$name" "$root") || return 1
    entries=$(jq --arg name "$name" --arg source "$source" 'map(if .name == $name then .source = $source else . end)' <<< "$entries") || return 1
  done <<< "$names"
  printf '%s\n' "$entries"
}

# Lix and upstream Nix both need these features; sudo must wrap the same argv.
smm_nix() {
  if [ "${1:-}" = --sudo ]; then
    shift
    sudo nix --extra-experimental-features 'nix-command flakes' "$@"
  else
    nix --extra-experimental-features 'nix-command flakes' "$@"
  fi
}

# Executable hooks let integration tests exercise real git without live apps.
smm_run_validate() {
  if [ -z "${SMM_VALIDATE_CMD:-}" ]; then smm_validate "$@"; return "$?"; fi
  local output result=0
  export SMM_FAILED_LINKS=''
  output=$("$SMM_VALIDATE_CMD" "$@") || result=$?
  [ -z "$output" ] || printf '%s\n' "$output"
  SMM_FAILED_LINKS=$(awk '/^fail / {sub(/:$/, "", $2); printf "%s%s", sep, $2; sep=" "}' <<< "$output")
  return "$result"
}
smm_run_apply() {
  if [ -n "${SMM_APPLY_CMD:-}" ]; then "$SMM_APPLY_CMD" "$@"; else cmd_apply "$@"; fi
}

smm_safe_relative() {
  case "/$1/" in *'/../'*|*'/./'*|*'//'*) return 1 ;; esac
  case "$1" in ''|*$'\n'*|*$'\t'*) return 1 ;; esac
}
smm_backup_dir() {
  local backup=${SMM_BACKUP:-$HOME/.smm-backup/$(date +%Y%m%d-%H%M%S)}
  mkdir -p "$backup" || return 1
  printf '%s\n' "$backup"
}
# Check existing ancestors as well as lexical traversal before changing sources.
smm_config_source_safe() {
  local source=$1 repo parent
  smm_safe_relative "$source" || return 1
  case "$source" in config/*) ;; *) return 1 ;; esac
  repo=$(cd "$(smm_repo)" && pwd -P) || return 1
  parent="$repo/$(dirname "$source")"
  while [ ! -d "$parent" ]; do
    [ ! -L "$parent" ] || return 1
    parent=$(dirname "$parent")
  done
  parent=$(cd "$parent" && pwd -P) || return 1
  case "$parent/" in "$repo/"*) ;; *) return 1 ;; esac
  [ ! -L "$repo/$source" ]
}

smm_has_tty() { ( : </dev/tty ) 2>/dev/null; }
# Home Manager may link through several store symlinks.
smm_linked_to() {
  [ -L "$1" ] && [ "$(readlink -f "$1")" = "$(readlink -f "$2")" ]
}
